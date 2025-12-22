//
//  HomeView.swift
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

import SwiftUI
import ConnectionManagerKit

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(SocketReceiver.self) var socketReceiver
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var path: [HomeRoute] = []
    @State var notificationText = ""
    
    var welcomeName: String {
        authenticationViewModel.user?.name
        ?? authenticationViewModel.user?.email
        ?? "Friend"
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                // in-app notifications are handled globally via AppNotificationBanner overlay
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Header
                    HStack(alignment: .center, spacing: AppSpacing.md) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Welcome back")
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                            Text(welcomeName)
                                .font(AppFont.title())
                                .lineLimit(1)
                            Text("Dashboard overview")
                                .font(AppFont.subheadline())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink(value: HomeRoute.profile) {
                            Image("Logo", bundle: .module)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.appColor.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if authenticationViewModel.user?.isAdmin == true {
                        MerchantControlsSection { route in
                            path.append(route)
                        }
#if canImport(CoreML)
                        PrimaryButton(title: "Train Data") {
                            Task.detached {
                                let service = try await MLService()
                                await service.startTraining()
                            }
                        }
#endif
                        Divider()
                        CustomerControlsSection { route in
                            path.append(route)
                        }
                    } else {
                        CustomerControlsSection { route in
                            path.append(route)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.lg)
            }
            .background(Color.backgroundColor)
            .navigationTitle("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                DestinationView(route: route)
            }
            .onChange(of: path) { _, _ in
                // Hide transient banners before navigating to reduce CA transaction size
                appNotificationCenter.hide()
            }
        }
    }
}

// MARK: - Routing
// moved to Models/HomeRoute.swift


struct DestinationView: View {
    let route: HomeRoute
    var body: some View {
        switch route {
        case .reservations: ReservationsView()
        case .peakTimes: ReportsView()
        case .inventory: InventoryView()
        case .team: TeamView()
        case .menuPricing: MenuPricingView()
        case .reports: ReportsView()
        case .menu: MenuView()
        case .orderNow: OrderFlowView()
        case .reserveTable: TableReservationView()
        case .myOrders: MyOrdersView()
        case .support: SupportView()
        case .profile: ProfileView()
        }
    }
}

// Removed PlaceholderScreen now that destinations are functional

// MARK: - Sections

struct MerchantControlsSection: View {
    var onSelect: @MainActor (HomeRoute) -> Void
    
#if os(Android)
    let reservationIcon = "android_calendar"
    let peakTimeIcon = "bars_time"
    let inventoryIcon = "android_package"
    let teamIcon = "android_group"
    let menuIcon = "android_note"
    let reportsIcon = "android_doc"
#else
    let reservationIcon = "calendar.badge.clock"
    let peakTimeIcon = "chart.bar.fill"
    let inventoryIcon = "shippingbox.fill"
    let teamIcon = "person.2.fill"
    let menuIcon = "square.and.pencil"
    let reportsIcon = "doc.text.magnifyingglass"
#endif
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SectionHeader(title: "Merchant console", subtitle: "Operations & insights")
            GridMenu(
                items: [
                    .init(title: "Reservations", systemName: reservationIcon, route: .reservations),
                    .init(title: "Peak times", systemName: peakTimeIcon, route: .peakTimes),
                    .init(title: "Inventory", systemName: inventoryIcon, route: .inventory),
                    .init(title: "Team", systemName: teamIcon, route: .team),
                    .init(title: "Menu & pricing", systemName: menuIcon, route: .menuPricing),
                    .init(title: "Reports", systemName: reportsIcon, route: .reports)
                ]
            ) { item in onSelect(item.route) }
        }
    }
}

struct CustomerControlsSection: View {
    var onSelect: @MainActor (HomeRoute) -> Void
    
#if os(Android)
    let cartFillIcon = "cart.fill"
    let calendarIcon = "calendar"
    let trayFullFill = "orders"
    let questionMarkCircleFill = "contact_support"
    let coffeeIcon = "android_coffee_cup"
#else
    let cartFillIcon = "cart.fill"
    let calendarIcon = "calendar"
    let trayFullFill = "tray.full.fill"
    let questionMarkCircleFill = "questionmark.circle.fill"
    let coffeeIcon = "cup.and.saucer.fill"
#endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Explore the menu")
                    .font(AppFont.headline())
                CardContainer(
                    padding: AppSpacing.md,
                    cornerRadius: 18,
                    backgroundColor: Color.appColor,
                    borderColor: nil,
                    borderWidth: 0,
                    shadowEnabled: true,
                    shadowColor: Color.appColor.opacity(0.35),
                    shadowRadius: 14,
                    shadowX: 0,
                    shadowY: 8
                ) {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: coffeeIcon)
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check what's available")
                                .font(AppFont.headline())
                                .foregroundStyle(.white)
                            Text("Tap to browse items")
                                .font(AppFont.caption())
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                        PrimaryButton(title: "View Menu") {
                            onSelect(.menu)
                        }
                        .frame(maxWidth: 160)
                    }
                }
            }
            
            SectionHeader(title: "Ordering & reservations", subtitle: "Place an order or book a table")
            GridMenu(
                items: [
                    .init(title: "Order now", systemName: cartFillIcon, route: .orderNow),
                    .init(title: "Reserve a table", systemName: calendarIcon, route: .reserveTable),
                    .init(title: "My orders", systemName: trayFullFill, route: .myOrders),
                    .init(title: "Help & support", systemName: questionMarkCircleFill, route: .support)
                ]
            ) { item in onSelect(item.route) }
            
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("Top selling items")
                        .font(AppFont.headline())
                    Spacer()
                    Button("View All") {}
                        .font(AppFont.footnote())
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                VStack(spacing: AppSpacing.sm) {
                    StatPillView(left: "Best", center: "Anna", right: "1500")
                    StatPillView(left: "John", center: "1200 sales.", right: "Emma")
                    StatPillView(left: "1000", center: "Mike", right: "800 sales.")
                    StatPillView(left: "Team", center: "You", right: "500")
                }
            }
        }
    }
}

// MARK: - Lightweight UI helpers

struct AvatarButton: View {
    var title: String
    var action: @MainActor () -> Void
    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Button(action: action) {
                Image("Logo", bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CircleActionButton: View {
    var systemName: String
    var action: @MainActor () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.appColor)
                    .frame(width: 54, height: 54)
                Image(systemName: systemName)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FeatureCircle: View {
    var title: String
    var systemName: String
    var action: @MainActor () -> Void
    var diameter: CGFloat = 140
    
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle().fill(Color.appColor)
                    .frame(width: diameter, height: diameter)
                Image(systemName: systemName)
                    .foregroundStyle(.white)
                    .font(.system(size: 44, weight: .semibold))
            }
            Text(title)
                .font(.headline)
        }
    }
}

struct StatPillView: View {
    var left: String
    var center: String
    var right: String
    
    var body: some View {
        CardContainer(
            padding: AppSpacing.md,
            cornerRadius: 22,
            backgroundColor: Color.appColor.opacity(0.12),
            borderColor: Color.appColor.opacity(0.2),
            borderWidth: 1,
            shadowEnabled: false
        ) {
            HStack(spacing: AppSpacing.md) {
                Text(left)
                    .font(.headline)
                Spacer(minLength: 4)
                HStack(spacing: AppSpacing.md) {
                    Image("Logo", bundle: .module)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    Text(center)
                        .font(.headline)
                }
                Text(right)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared Building Blocks

struct SectionHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.headline())
            Text(subtitle)
                .font(AppFont.subheadline())
                .foregroundStyle(.secondary)
                .accessibilityHidden(subtitle.isEmpty)
        }
    }
}

struct GridMenu: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let systemName: String
        let route: HomeRoute
    }
    var items: [Item]
    var onTap: @MainActor (Item) -> Void
    
    private let columnCount: Int = 2
    private var preferredDiameter: CGFloat {
#if canImport(UIKit)
        let screenWidth = UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = AppSpacing.lg * 2
        let interItemSpacing: CGFloat = AppSpacing.lg
        let columns = CGFloat(columnCount)
        let available = max(0, screenWidth - horizontalPadding - interItemSpacing * (columns - 1))
        let columnWidth = available / columns
        return min(140, max(100, columnWidth))
#else
        return 140
#endif
    }
    
    private var rows: [[Item]] {
        var result: [[Item]] = []
        var i = 0
        while i < items.count {
            let end = min(i + columnCount, items.count)
            result.append(Array(items[i..<end]))
            i += columnCount
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                let row = rows[rowIndex]
                HStack(spacing: AppSpacing.lg) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        if col < row.count {
                            let item = row[col]
                            Button { onTap(item) } label: {
                                FeatureCircle(
                                    title: item.title,
                                    systemName: item.systemName,
                                    action: {},
                                    diameter: preferredDiameter)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}


