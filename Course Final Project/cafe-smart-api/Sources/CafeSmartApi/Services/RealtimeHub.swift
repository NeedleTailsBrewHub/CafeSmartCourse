//
//  RealtimeHub.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

import BinaryCodable
import ConnectionManagerKit
import Foundation
import JWT
import JWTKit
import NIOCore
import NIOSSL
import NIOWebSocket
import Vapor
#if canImport(Network)
import Network
#endif

enum OrderInfo: Codable, Sendable, Equatable {
  case created(Order)
  case updated(Order)
  case deleted(Order)
}

enum InventoryInfo: Codable, Sendable, Equatable {
  case runningLow(InventoryItem)
  case restocked(InventoryItem)
  case outOfStock(InventoryItem)
  case reordered(InventoryItem)
}

enum ReservationInfo: Codable, Sendable, Equatable {
  case created(Reservation)
  case updated(Reservation)
  case deleted(Reservation)
}

/// First binary frame after connect. Wire name must match clients.
public struct WSAuthPacket: Codable, Sendable, Equatable {
  public var token: String
  public var topic: String

  public init(token: String, topic: String) {
    self.token = token
    self.topic = topic
  }
}

// MARK: - RealtimeHub (CMK WebSocket server)

actor RealtimeHub {

  enum MessagePacket: Codable, Sendable, Equatable {
    case order(OrderInfo)
    case inventory(InventoryInfo)
    case reservation(ReservationInfo)
    case modelUploaded(MLModelArtifact)
    case modelActivated(kind: PredictorKind, id: String)
    case modelDeleted(id: String)
    case predictorReady(kind: PredictorKind)
    case restockDecisions([CafePredictorController.RestockDecisionResponse])
    case none
  }

  enum Topic: String, Equatable, Sendable {
    case merchant
    case customer
  }

  private struct ConnectionState {
    var writer: NIOAsyncChannelOutboundWriter<WebSocketFrame>?
    var topic: Topic?
    var authenticated: Bool
  }

  private let listener = ConnectionListener<WebSocketFrame, WebSocketFrame>()
  private var connections: [String: ConnectionState] = [:]
  private var listenTask: Task<Void, Never>?
  private var authTimeouts: [String: Task<Void, Never>] = [:]
  private var boundContinuation: CheckedContinuation<Int, any Error>?
  private(set) var boundPort: Int?

  private var jwtKeys: JWTKeyCollection?
  private var store: (any MongoStore)?
  private var logger: Logger?

  /// Start CMK WebSocket listener (separate port from Vapor HTTP).
  func start(using app: Application) async throws {
    if listenTask != nil { return }

    self.jwtKeys = app.jwt.keys
    self.store = app.mongoStore
    self.logger = app.logger

    let defaultPort = app.environment == .testing ? 0 : 8081
    let port = Environment.get("WS_PORT").flatMap(Int.init) ?? defaultPort
    let host = Environment.get("WS_HOST") ?? "0.0.0.0"

    let config = Configuration(group: app.eventLoopGroup, host: host, port: port)
    let resolved = try await listener.resolveAddress(config)
    let contextDelegate = CMKRealtimeContextDelegate(hub: self, listener: listener)
    let connectionDelegate = CMKRealtimeConnectionDelegate(
      listener: listener, contextDelegate: contextDelegate)
    let listenerDelegate = CMKRealtimeListenerDelegate(hub: self)

    listenTask = Task { [listener] in
      do {
        try await listener.listen(
          address: resolved.address!,
          websocketConfiguration: .init(maxFrameSize: 1 << 20),
          configuration: resolved,
          delegate: connectionDelegate,
          listenerDelegate: listenerDelegate
        )
      } catch {
        app.logger.error("CMK WebSocket listener stopped: \(error)")
      }
    }

    boundPort = try await withCheckedThrowingContinuation { continuation in
      self.boundContinuation = continuation
    }
    app.logger.info("CMK WebSocket server listening on \(host):\(boundPort ?? port)")
  }

  func stop() async {
    for task in authTimeouts.values { task.cancel() }
    authTimeouts.removeAll()
    connections.removeAll()
    await listener.serviceGroup?.triggerGracefulShutdown()
    try? await listener.shutdown()
    listenTask?.cancel()
    listenTask = nil
    boundPort = nil
  }

  func didBind(port: Int?) {
    if let continuation = boundContinuation {
      boundContinuation = nil
      if let port {
        boundPort = port
        continuation.resume(returning: port)
      } else {
        continuation.resume(throwing: Abort(.internalServerError, reason: "WS bind failed"))
      }
    } else if let port {
      boundPort = port
    }
  }

  func registerWriter(
    id: String, writer: NIOAsyncChannelOutboundWriter<WebSocketFrame>
  ) {
    var state = connections[id] ?? ConnectionState(writer: nil, topic: nil, authenticated: false)
    state.writer = writer
    connections[id] = state
    scheduleAuthTimeout(for: id)
  }

  func removeConnection(id: String) {
    authTimeouts.removeValue(forKey: id)?.cancel()
    connections.removeValue(forKey: id)
  }

  func handleInbound(id: String, frame: WebSocketFrame, buffer: ByteBuffer) async {
    switch frame.opcode {
    case .ping:
      let pong = WebSocketFrame(fin: true, opcode: .pong, data: buffer)
      try? await connections[id]?.writer?.write(pong)
      return
    case .connectionClose:
      await listener.shutdownChildChannel(id: id)
      removeConnection(id: id)
      return
    case .binary, .text:
      break
    default:
      return
    }

    var mutable = buffer
    guard let bytes = mutable.readBytes(length: mutable.readableBytes) else { return }
    let data = Data(bytes)

    guard let state = connections[id] else { return }

    if !state.authenticated {
      await authenticate(id: id, data: data)
      return
    }

    guard let topic = state.topic else { return }
    // Fan-out peer binary frames to same topic (authenticated only)
    for (peerId, peer) in connections where peer.authenticated && peer.topic == topic && peerId != id
    {
      guard let writer = peer.writer else { continue }
      var out = ByteBufferAllocator().buffer(capacity: bytes.count)
      out.writeBytes(bytes)
      let outFrame = WebSocketFrame(fin: true, opcode: .binary, data: out)
      try? await writer.write(outFrame)
    }
  }

  private func authenticate(id: String, data: Data) async {
    authTimeouts.removeValue(forKey: id)?.cancel()

    guard let packet = try? BinaryDecoder().decode(WSAuthPacket.self, from: data),
      let topic = Topic(rawValue: packet.topic.lowercased()),
      let jwtKeys,
      let store
    else {
      await reject(id: id, reason: "invalid auth packet")
      return
    }

    do {
      let verified = try await jwtKeys.verify(packet.token, as: UserJWT.self)
      guard let user = try await store.findUser(byId: verified.subject.value) else {
        await reject(id: id, reason: "unknown user")
        return
      }
      if topic == .merchant && !user.isAdmin {
        await reject(id: id, reason: "merchant topic requires admin")
        return
      }
      var state = connections[id] ?? ConnectionState(writer: nil, topic: nil, authenticated: false)
      state.authenticated = true
      state.topic = topic
      connections[id] = state
      logger?.info("WS authenticated user=\(user.id) topic=\(topic.rawValue)")
    } catch {
      await reject(id: id, reason: "jwt verification failed")
    }
  }

  private func reject(id: String, reason: String) async {
    logger?.warning("WS auth rejected (\(reason)) id=\(id)")
    if let writer = connections[id]?.writer {
      let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: ByteBuffer())
      try? await writer.write(close)
      writer.finish()
    }
    await listener.shutdownChildChannel(id: id)
    removeConnection(id: id)
  }

  private func scheduleAuthTimeout(for id: String) {
    authTimeouts[id]?.cancel()
    let timeoutSeconds: Double = (Environment.get("WS_AUTH_TIMEOUT_SECONDS").flatMap(Double.init)) ?? 5
    authTimeouts[id] = Task {
      try? await Task.sleep(for: .seconds(timeoutSeconds))
      guard !Task.isCancelled else { return }
      let state = self.connections[id]
      if state?.authenticated != true {
        await self.reject(id: id, reason: "auth timeout")
      }
    }
  }

  func publish(_ packet: MessagePacket, to topic: Topic) async {
    do {
      let data = try BinaryEncoder().encode(packet)
      var buffer = ByteBufferAllocator().buffer(capacity: data.count)
      buffer.writeBytes(data)
      let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
      for (_, entry) in connections where entry.authenticated && entry.topic == topic {
        guard let writer = entry.writer else { continue }
        try? await writer.write(frame)
      }
    } catch {
      logger?.error("RealtimeHub.publish error: \(error)")
    }
  }
}

// MARK: - CMK Delegates

private final class CMKRealtimeListenerDelegate: ListenerDelegate, @unchecked Sendable {
  private let hub: RealtimeHub

  init(hub: RealtimeHub) {
    self.hub = hub
  }

  func retrieveChannelHandlers() -> [any ChannelHandler] { [] }
  func retrieveSSLHandler() -> NIOSSLServerHandler? { nil }

  func didBindWebSocketServer<Inbound: Sendable, Outbound: Sendable>(
    channel: NIOAsyncChannel<EventLoopFuture<NIOAsyncChannel<Inbound, Outbound>>, Never>
  ) async {
    await hub.didBind(port: channel.channel.localAddress?.port)
  }
}

private final class CMKRealtimeConnectionDelegate: ConnectionDelegate, @unchecked Sendable {
  private let listener: ConnectionListener<WebSocketFrame, WebSocketFrame>
  private let contextDelegate: CMKRealtimeContextDelegate

  init(
    listener: ConnectionListener<WebSocketFrame, WebSocketFrame>,
    contextDelegate: CMKRealtimeContextDelegate
  ) {
    self.listener = listener
    self.contextDelegate = contextDelegate
  }

  #if canImport(Network)
    func handleError(_ stream: AsyncStream<NWError>, id: String) {}
    func handleNetworkEvents(
      _ stream: AsyncStream<NetworkEventMonitor.NetworkEvent>, id: String
    ) async {}
  #else
    func handleError(_ stream: AsyncStream<IOError>, id: String) {}
    func handleNetworkEvents(
      _ stream: AsyncStream<NetworkEventMonitor.NIOEvent>, id: String
    ) async {}
  #endif

  func initializedChildChannel<Outbound: Sendable, Inbound: Sendable>(
    _ context: ChannelContext<Inbound, Outbound>
  ) async {
    await listener.setContextDelegate(contextDelegate, key: context.id)
  }
}

private final class CMKRealtimeContextDelegate: ChannelContextDelegate, @unchecked Sendable {
  private let hub: RealtimeHub
  private let listener: ConnectionListener<WebSocketFrame, WebSocketFrame>

  init(hub: RealtimeHub, listener: ConnectionListener<WebSocketFrame, WebSocketFrame>) {
    self.hub = hub
    self.listener = listener
  }

  func deliverWriter<Outbound, Inbound>(
    context: WriterContext<Inbound, Outbound>
  ) async {
    guard Outbound.self == WebSocketFrame.self,
      let writer = context.writer as? NIOAsyncChannelOutboundWriter<WebSocketFrame>
    else { return }
    await hub.registerWriter(id: context.id, writer: writer)
  }

  func deliverInboundBuffer<Inbound: Sendable, Outbound: Sendable>(
    context: StreamContext<Inbound, Outbound>
  ) async {
    guard let frame = context.inbound as? WebSocketFrame else { return }
    let buffer = await listener.unmaskedData(frame)
    await hub.handleInbound(id: context.id, frame: frame, buffer: buffer)
  }

  func channelActive(_ stream: AsyncStream<Void>, id: String) {}

  func channelInactive(_ stream: AsyncStream<Void>, id: String) {
    Task { await hub.removeConnection(id: id) }
  }

  func reportChildChannel(error: any Error, id: String) async {
    await hub.removeConnection(id: id)
  }

  func didShutdownChildChannel() async {}
}

// MARK: - Application Storage

extension Application {
  private struct RealtimeKey: StorageKey { typealias Value = RealtimeHub }
  var realtimeHub: RealtimeHub {
    get {
      if let hub = storage[RealtimeKey.self] { return hub }
      let hub = RealtimeHub()
      storage[RealtimeKey.self] = hub
      return hub
    }
    set { storage[RealtimeKey.self] = newValue }
  }
}

