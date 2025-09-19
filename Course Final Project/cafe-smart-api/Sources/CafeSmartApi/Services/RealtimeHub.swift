//
//  RealtimeHub.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/28/25.
//
import Vapor
import BSON

actor RealtimeHub {

    enum Topic: Equatable {
        case merchant, customer
    }
    
    private var connections: [ObjectIdentifier: (topic: Topic, ws: WebSocket)] = [:]
    nonisolated(unsafe) var task: Task<Void, Never>?
    
    func subscribe(topic: Topic, ws: WebSocket) async {
        let id = ObjectIdentifier(ws)
        connections[id] = (topic: topic, ws: ws)
        
        
        ws.onBinary { [weak self] ws, buffer in
            //recieve information
            var buffer = buffer
            guard let self else { return }
            if let bytes: [UInt8] = buffer.readBytes(length: buffer.readableBytes) {
                for connection in await self.connections.values.filter({ $0.topic == topic }) {
                    do {
                        try await connection.ws.send(bytes)
                    } catch {
                        print("Failed to send message \(error)")
                    }
                }
            }
        }
        
        
        ws.onClose.whenComplete { [weak self] _ in
            guard let self else { return }
            if task?.isCancelled == false {
                task?.cancel()
            }
            task = Task { [weak self] in
                guard let self else { return }
                await self.purge(ws: ws)
            }
        }
    }
    
    
    private func purge(ws: WebSocket) {
        let id = ObjectIdentifier(ws)
        connections.removeValue(forKey: id)
    }
    
    
    enum MessagePacket: Codable, Sendable, Equatable {
        case order(OrderInfo)
        case inventory(InventoryInfo)
//        case reservation(ReservationInfo)
        case modelUploaded(MLModelArtifact)
        case modelActivated(kind: PredictorKind, id: String)
        case modelDeleted(id: String)
        case predictorReady(kind: PredictorKind)
        case none
    }
    
    func publish(_ packet: MessagePacket, to topic: Topic) async {
        Task {
            do {
                let data = try BSONEncoder().encode(packet).makeData()
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                for (_, entry) in connections where entry.topic == topic {
                    entry.ws.send(buffer)
                }
            } catch {
                print("RealtimeHub publish error: \(error)")
            }
        }
    }
}


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

//enum ReservationInfo: Codable, Sendable, Equatable {
//  case created(Reservation)
//  case updated(Reservation)
//  case deleted(Reservation)
//}
