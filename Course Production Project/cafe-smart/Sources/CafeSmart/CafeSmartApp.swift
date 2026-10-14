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
import VenueSmartKit

/// A logger for the CafeSmart host module.
let logger: Logger = Logger(subsystem: "com.example.app", category: "CafeSmart")

extension Notification.Name {
    static let cafeSmartAppResume = Notification.Name("CafeSmartAppResume")
}

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
/* SKIP @bridge */public struct CafeSmartRootView: View {
    /* SKIP @bridge */public init() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "cafe-smart-url-cache"
        )
        VenueSmartAPIConfiguration.shared = .makeDefault()
    }

    @State var authenticationViewModel = AuthenticationViewModel()
    @State var businessViewModel = BusinessViewModel()
    @State var inventoryViewModel = InventoryViewModel()
    @State var menuViewModel = MenuViewModel()
    @State var orderViewModel = OrderViewModel()
    @State var cartViewModel = CartViewModel()
    @State var reservationViewModel = ReservationViewModel()
    @State var teamViewModel = TeamViewModel()
    @State var tagViewModel = TagViewModel()
    @State var seatingViewModel = SeatingViewModel()
    @State var recipesViewModel = RecipesViewModel()
    @State var supportViewModel = SupportViewModel()
    @State var homeNavigator = HomeNavigator()
    @State var appNotificationCenter = AppNotificationCenter()
    @State var realtime = VenueSmartRealtimeClient()

    public var body: some View {
        ContentView()
            .environment(authenticationViewModel)
            .environment(businessViewModel)
            .environment(inventoryViewModel)
            .environment(menuViewModel)
            .environment(orderViewModel)
            .environment(cartViewModel)
            .environment(reservationViewModel)
            .environment(teamViewModel)
            .environment(tagViewModel)
            .environment(seatingViewModel)
            .environment(recipesViewModel)
            .environment(supportViewModel)
            .environment(homeNavigator)
            .environment(realtime.socketReceiver)
            .environment(appNotificationCenter)
            .environment(\.merchantGuestDestinations, MerchantGuestDestinations(
                orderFlow: AnyView(OrderFlowView()),
                reserveTable: AnyView(TableReservationView()),
                myOrders: AnyView(MyOrdersView()),
                support: AnyView(SupportView()),
                profile: AnyView(ProfileView())
            ))
            .task {
                wireRealtime()
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
            .overlay(alignment: .top) {
                AppNotificationBanner()
                    .environment(appNotificationCenter)
            }
            .onChange(of: realtime.socketReceiver.webSocketFrame) { _, frame in
                realtime.handleFrame(frame)
            }
            .onChange(of: authenticationViewModel.didSignIn) { _, signedIn in
                guard signedIn else { return }
                Task { @MainActor in
                    await menuViewModel.checkCatalogVersion()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cafeSmartAppResume)) { _ in
                Task { @MainActor in
                    await authenticationViewModel.resumeRealtimeIfNeeded()
                    if authenticationViewModel.didSignIn {
                        await menuViewModel.checkCatalogVersion()
                        let isAdmin = authenticationViewModel.user?.isAdmin == true
                        if isAdmin {
                            try? await orderViewModel.fetchKitchenBoard()
                            try? await reservationViewModel.fetchReservations(reset: true)
                            try? await inventoryViewModel.fetchInventory(reset: true)
                        } else {
                            try? await orderViewModel.fetchOrders(reset: true)
                            try? await reservationViewModel.fetchReservations(reset: true)
                        }
                    }
                }
            }
    }

    @MainActor
    private func wireRealtime() {
        realtime.authenticationViewModel = authenticationViewModel
        realtime.orderViewModel = orderViewModel
        realtime.inventoryViewModel = inventoryViewModel
        realtime.menuViewModel = menuViewModel
        realtime.reservationViewModel = reservationViewModel
        realtime.onHostEvent = { [appNotificationCenter] event in
            handleHostEvent(event, notifications: appNotificationCenter)
        }
        authenticationViewModel.onRealtimeSessionReady = { [realtime] in
            await realtime.connectFromSession()
        }
        authenticationViewModel.onRealtimeSessionEnded = { [realtime] in
            await realtime.stop()
        }
    }

    @MainActor
    private func handleHostEvent(_ event: RealtimeHostEvent, notifications: AppNotificationCenter) {
        let isAdmin = authenticationViewModel.user?.isAdmin == true
        let userId = authenticationViewModel.user?.id
        switch event {
        case .orderCreated(let order):
            if isAdmin {
                let count = order.items.count
                let customer = order.customerName?.isEmpty == false
                    ? order.customerName! : "New customer"
                let summary = count > 0
                    ? "New order (\(count) items): \(customer)"
                    : "New order: \(customer)"
                notifications.show(summary, iconSystemName: "bell.fill", duration: 2.5)
            } else if order.customerUserId == userId {
                notifications.show(
                    "Order #\(order.id.prefix(6).uppercased()) placed",
                    iconSystemName: "checkmark.circle.fill",
                    duration: 2.5)
            }
        case .orderUpdated(let order):
            if isAdmin || order.customerUserId == userId {
                notifications.show(
                    "Order #\(order.id.prefix(6).uppercased()) → \(guestStatusLabel(order.status))",
                    iconSystemName: "arrow.triangle.2.circlepath",
                    duration: 2.0)
            }
        case .orderDeleted:
            break
        case .inventoryRunningLow(let item):
            notifications.show(
                "Inventory running low: \(item.name) (\(item.quantity) \(item.unit))",
                iconSystemName: "exclamationmark.triangle.fill",
                duration: 3.0)
        case .modelUploaded(let artifact):
            let runtime = artifact.runtime?.rawValue ?? "model"
            notifications.show(
                "Model ready: \(artifact.kind.rawValue) (\(runtime))",
                iconSystemName: "checkmark.seal.fill",
                duration: 3.0)
            #if os(macOS)
            Task { await ModelsAdminViewModel.shared.refresh() }
            #endif
        case .modelActivated(let kind, let id):
            notifications.show(
                "Model activated: \(kind.rawValue) (\(id.prefix(8))…)",
                iconSystemName: "checkmark.circle.fill",
                duration: 2.5)
            #if os(macOS)
            Task { await ModelsAdminViewModel.shared.refresh() }
            #endif
        case .modelDeleted(let id):
            notifications.show(
                "Model deleted (\(id.prefix(8))…)",
                iconSystemName: "trash.fill",
                duration: 2.5)
            #if os(macOS)
            Task { await ModelsAdminViewModel.shared.refresh() }
            #endif
        case .predictorReady(let kind):
            notifications.show(
                "Predictor ready: \(kind.rawValue)",
                iconSystemName: "bolt.badge.a.fill",
                duration: 2.5)
        case .restockDecisions(let decisions):
            let need = decisions.filter(\.needRestock).count
            let ok = decisions.count - need
            notifications.show(
                "Restock forecast: \(need) need reorder, \(ok) OK (\(decisions.count) SKUs)",
                iconSystemName: need > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                duration: 3.5)
        case .catalogVersion:
            break
        case .reservationCreated(let reservation):
            if isAdmin {
                notifications.show(
                    "Reservation: \(reservation.name) · party \(reservation.partySize)",
                    iconSystemName: "calendar.badge.plus",
                    duration: 2.5)
            }
        case .reservationUpdated, .reservationDeleted:
            break
        }
    }

    private func guestStatusLabel(_ status: OrderStatus) -> String {
        switch status {
        case .pending: return "Received"
        case .preparing: return "Preparing"
        case .ready: return "Ready for pickup"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }
}

/* SKIP @bridge */public final class CafeSmartAppDelegate: Sendable {
    /* SKIP @bridge */public static let shared = CafeSmartAppDelegate()

    private init() {}

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
        NotificationCenter.default.post(name: .cafeSmartAppResume, object: nil)
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
