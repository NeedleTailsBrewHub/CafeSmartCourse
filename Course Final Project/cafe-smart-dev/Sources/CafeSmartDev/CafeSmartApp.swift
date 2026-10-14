import Foundation
import SkipFuse
import SwiftUI
import ConnectionManagerKit
import BinaryCodable

/// A logger for the CafeSmartApp module.
let logger: Logger = Logger(subsystem: "com.cafesmart.dev", category: "CafeSmartApp")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct CafeSmartDevRootView : View {
    
    @State var authenticationViewModel = AuthenticationViewModel()
    @State var inventoryViewModel = InventoryViewModel()
    @State var menuViewModel = MenuViewModel()
    @State var orderViewModel = OrderViewModel()
    @State var cartViewModel = CartViewModel()
    @State var appNotificationCenter = AppNotificationCenter()
    @State var notifications: [SocketReceiver.WebSocketOpcode] = []
    @State var isRunning = false
    let socket = WebSocketClient.shared
    
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        ContentView()
            .environment(authenticationViewModel)
            .environment(inventoryViewModel)
            .environment(menuViewModel)
            .environment(orderViewModel)
            .environment(cartViewModel)
            .environment(socket.socketReceiver)
            .environment(appNotificationCenter)
            .overlay(alignment: .top) {
                AppNotificationBanner()
                    .environment(appNotificationCenter)
            }
            .onChange(of: socket.socketReceiver.webSocketFrame) { _, frame in
                guard let frame else { return }
                notifications.append(frame)
                if !isRunning {
                    isRunning = true
                    defer { isRunning = false }
                    while !notifications.isEmpty {
                        switch notifications.removeFirst() {
                        case .binary(let data):
                            guard let data else { continue }
                            if let order: CreateOrderRequest = try? BinaryDecoder().decode(CreateOrderRequest.self, from: data) {
                                let count = order.items.count
                                let customer = order.customerName?.isEmpty == false ? order.customerName! : "New customer"
                                let summary = count > 0 ? "New order (\(count) items): \(customer)" : "New order: \(customer)"
                                if authenticationViewModel.user?.isAdmin == true {
                                    appNotificationCenter.show(summary, iconSystemName: "bell.fill", duration: 2.0)
                                }
                            } else if let packet = try? BinaryDecoder().decode(MessagePacket.self, from: data) {
                                guard authenticationViewModel.user?.isAdmin == true else { continue }
                                switch packet {
                                case .inventory(let info):
                                    switch info {
                                    case .runningLow(let item):
                                        let message = "Inventory running low: \(item.name) (\(item.quantity) \(item.unit))"
                                        appNotificationCenter.show(message, iconSystemName: "exclamationmark.triangle.fill", duration: 3.0)
                                    default:
                                        continue
                                    }
                                case .modelUploaded(let artifact):
                                    let runtime = artifact.runtime?.rawValue ?? "model"
                                    appNotificationCenter.show(
                                        "Model ready: \(artifact.kind.rawValue) (\(runtime))",
                                        iconSystemName: "checkmark.seal.fill",
                                        duration: 3.0
                                    )
                                    #if os(macOS)
                                    Task { await ModelsAdminViewModel.shared.refresh() }
                                    #endif
                                case .modelActivated(let kind, let id):
                                    appNotificationCenter.show(
                                        "Model activated: \(kind.rawValue) (\(id.prefix(8))…)",
                                        iconSystemName: "checkmark.circle.fill",
                                        duration: 2.5
                                    )
                                    #if os(macOS)
                                    Task { await ModelsAdminViewModel.shared.refresh() }
                                    #endif
                                case .modelDeleted(let id):
                                    appNotificationCenter.show(
                                        "Model deleted (\(id.prefix(8))…)",
                                        iconSystemName: "trash.fill",
                                        duration: 2.5
                                    )
                                    #if os(macOS)
                                    Task { await ModelsAdminViewModel.shared.refresh() }
                                    #endif
                                case .predictorReady(let kind):
                                    appNotificationCenter.show(
                                        "Predictor ready: \(kind.rawValue)",
                                        iconSystemName: "bolt.badge.a.fill",
                                        duration: 2.5
                                    )
                                case .restockDecisions(let decisions):
                                    inventoryViewModel.applyRestockDecisions(decisions)
                                    let need = decisions.filter(\.needRestock).count
                                    let ok = decisions.count - need
                                    let message = "Restock forecast: \(need) need reorder, \(ok) OK (\(decisions.count) SKUs)"
                                    appNotificationCenter.show(
                                        message,
                                        iconSystemName: need > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                        duration: 3.5
                                    )
                                default:
                                    continue
                                }
                            }
                        default:
                            continue
                        }
                    }
                }
            }
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class CafeSmartDevAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = CafeSmartDevAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}

public enum MessagePacket: Codable, Sendable, Equatable {
    case order(OrderInfo)
    case inventory(InventoryInfo)
//    case reservation(ReservationInfo)
    case modelUploaded(MLModelArtifact)
    case modelActivated(kind: PredictorKind, id: String)
    case modelDeleted(id: String)
    case predictorReady(kind: PredictorKind)
    case restockDecisions([RestockDecisionResponse])
    case none
}

public struct RestockDecisionResponse: Codable, Sendable, Equatable {
    public let sku: String
    public let needRestock: Bool
    public let reorderQty: Int
    public let reorderPoint: Int
    public let leadTimeDays: Int
    public let onHand: Int
    public let forecastSumNextLeadTime: Int
}

public enum OrderInfo: Codable, Sendable, Equatable {
    case created(Order)
    case updated(Order)
    case deleted(Order)
}

public enum InventoryInfo: Codable, Sendable, Equatable {
    case runningLow(InventoryItem)
    case restocked(InventoryItem)
    case outOfStock(InventoryItem)
    case reordered(InventoryItem)
}

//public enum ReservationInfo: Codable, Sendable, Equatable {
//    case created(Reservation)
//    case updated(Reservation)
//    case deleted(Reservation)
//}
//

public struct MLModelArtifact: Codable, Sendable, Equatable {
    // Some endpoints may return `id` as String while others return `_id`
    public var id: String?
    public var _id: String?
    public var filename: String?
    public var runtime: PredictRuntime?
    public var kind: PredictorKind
    public var storedAt: String?
    public var bytes: Int?
    public var active: Bool
    public var uploadedAt: Date?
}

public struct ModelsList: Codable, Sendable, Equatable {
    public let items: [MLModelArtifact]
}

public struct TrainJobDTO: Codable, Sendable, Equatable {
    public var id: String
    public var status: String
    public var error: String?
    public var artifactId: String?
    public var kind: String?
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct TrainJobListDTO: Codable, Sendable, Equatable {
    public var items: [TrainJobDTO]
}

public enum PredictorKind: String, Codable, Sendable, CaseIterable, Equatable {
    case workloadHourly
    case reservationsHourly
    case restockDaily
    case reservationDuration
}

public enum PredictRuntime: String, Codable, Sendable, Equatable {
    case onnx
    case coreml
}
