//
//  CafeSmartApp.swift
//  CafeSmart
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
//

import Foundation
#if canImport(SkipFuse)
import SkipFuse
#endif
import SwiftUI
import ConnectionManagerKit
import BSON

/// A logger for the CafeSmart module.
let logger: Logger = Logger(subsystem: "com.needletails.cafesmart", category: "CafeSmart")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct CafeSmartRootView : View {
    /* SKIP @bridge */public init() {
    }
    
    @State var authenticationViewModel = AuthenticationViewModel()
    @State var businessViewModel = BusinessViewModel()
    @State var inventoryViewModel = InventoryViewModel()
    @State var menuViewModel = MenuViewModel()
    @State var orderViewModel = OrderViewModel()
    @State var reservationViewModel = ReservationViewModel()
    @State var teamViewModel = TeamViewModel()
    @State var appNotificationCenter = AppNotificationCenter()
    @State var notifications: [SocketReceiver.WebSocketOpcode] = []
    @State var isRunning = false
    let socket = WebSocketClient.shared
    
    public var body: some View {
        ContentView()
            .environment(authenticationViewModel)
            .environment(businessViewModel)
            .environment(inventoryViewModel)
            .environment(menuViewModel)
            .environment(orderViewModel)
            .environment(reservationViewModel)
            .environment(teamViewModel)
            .environment(socket.socketReceiver)
            .environment(appNotificationCenter)
            .environment(\.font, .custom("Roboto-Regular", size: 17))
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
            .overlay(alignment: .top) {
                AppNotificationBanner()
                    .environment(appNotificationCenter)
            }
            .onChange(of: socket.socketReceiver.webSocketFrame) { _, frame in
                guard let frame else { return }
                notifications.append(frame)
                if !isRunning {
                    isRunning = true
                    while !notifications.isEmpty {
                        switch notifications.removeLast() {
                        case .binary(let data):
                            guard let data else { return }
                            if let order: CreateOrderRequest = try? BSONDecoder().decode(CreateOrderRequest.self, from: Document(data: data)) {
                                let count = order.items.count
                                let customer = order.customerName?.isEmpty == false ? order.customerName! : "New customer"
                                let summary = count > 0 ? "New order (\(count) items): \(customer)" : "New order: \(customer)"
                                if authenticationViewModel.user?.isAdmin == true {
                                    appNotificationCenter.show(summary, iconSystemName: "bell.fill", duration: 2.0)
                                }
                            } else if let packet = try? BSONDecoder().decode(MessagePacket.self, from: Document(data: data)) {
                                switch packet {
                                case .inventory(let info):
                                    switch info {
                                    case .runningLow(let item):
                                        let message = "Inventory running low: \(item.name) (\(item.quantity) \(item.unit))"
                                        if authenticationViewModel.user?.isAdmin == true {
                                            appNotificationCenter.show(message, iconSystemName: "exclamationmark.triangle.fill", duration: 3.0)
                                        }
                                    default:
                                        continue
                                    }
                                default:
                                    continue
                                }
                            }
                        default:
                            continue
                        }
                    }
                    isRunning = false
                }
            }
    }
}


/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class CafeSmartAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = CafeSmartAppDelegate()
    
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
