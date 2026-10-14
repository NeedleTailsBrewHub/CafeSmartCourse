//
//  MacHomeView.swift
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

#if os(macOS)
import SwiftUI
import ConnectionManagerKit

struct MacHomeView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(SocketReceiver.self) var socketReceiver
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(InventoryViewModel.self) var inventoryViewModel
    @Environment(CartViewModel.self) private var cartViewModel
    @State var selection: HomeRoute? = nil
    @State var notificationText = ""
    @AppStorage("trainingLocation") private var trainingLocationRaw: String = "local"
    @Bindable private var modelsAdmin = ModelsAdminViewModel.shared

    private var isAdmin: Bool {
        authenticationViewModel.user?.isAdmin ?? false
    }

    private var trainingLocation: TrainingLocation {
        TrainingLocation(rawValue: trainingLocationRaw) ?? .local
    }

    private var welcomeName: String {
        authenticationViewModel.user?.name
        ?? authenticationViewModel.user?.email
        ?? "there"
    }

    private var inventoryIcon: String { "shippingbox.fill" }
    private var menuIcon: String { "square.and.pencil" }
    private var cartFillIcon: String { "cart.fill" }
    private var trayFullFill: String { "tray.full.fill" }

    private var availableMenuCount: Int {
        menuViewModel.items.filter(\.isAvailable).count
    }

    private var activeOrderCount: Int {
        orderViewModel.orders.filter {
            $0.status == .pending || $0.status == .preparing || $0.status == .ready
        }.count
    }

    private var lowStockCount: Int {
        inventoryViewModel.items.filter { $0.quantity <= $0.reorderThreshold }.count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Button {
                        selection = nil
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    .buttonStyle(.plain)
                    .tag(Optional<HomeRoute>.none)
                } header: {
                    Text("CaféSmart")
                }

                if isAdmin {
                    Section("Operations") {
                        sidebarRow(title: "Inventory", systemName: inventoryIcon, route: .inventory)
                        sidebarRow(title: "Menu & pricing", systemName: menuIcon, route: .menuPricing)
                        sidebarRow(title: "Models & training", systemName: "cpu", route: .models)
                    }
                }

                Section("Ordering") {
                    sidebarRow(title: "Order", systemName: cartFillIcon, route: .orderNow)
                    sidebarRow(title: "Orders", systemName: trayFullFill, route: .myOrders)
                }

                Section("Account") {
                    sidebarRow(title: "Profile", systemName: "person.crop.circle", route: .profile)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("CaféSmart")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            Group {
                if let selection {
                    DestinationView(route: selection)
                        .navigationTitle(title(for: selection))
                } else {
                    dashboard
                        .navigationTitle("Home")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.groupedBackgroundColor)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if isAdmin {
                        Menu {
                            Picker("Training location", selection: $trainingLocationRaw) {
                                Text("On this Mac (Create ML → CoreML)").tag("local")
                                Text("On API server (Python → ONNX)").tag("server")
                            }
                            Button("Train Now") {
                                let location = trainingLocation
                                Task {
                                    do {
                                        let message = try await modelsAdmin.train(location: location)
                                        appNotificationCenter.show(message, iconSystemName: "checkmark.circle.fill", duration: 3.0)
                                    } catch {
                                        logger.info("Error Training Data Model: \(error)")
                                        appNotificationCenter.show(
                                            "Training failed: \(error.localizedDescription)",
                                            iconSystemName: "xmark.octagon.fill",
                                            duration: 4.0
                                        )
                                    }
                                }
                            }
                            .disabled(modelsAdmin.isTraining || (trainingLocation == .server && !modelsAdmin.serverTrainingAvailable))
                            Button("Open Models…") {
                                selection = .models
                            }
                        } label: {
                            Label("Train Data", systemImage: "bolt.badge.a.fill")
                        }
                        .help("Train restock models")
                    }
                    if !cartViewModel.isEmpty {
                        Button {
                            selection = .orderNow
                        } label: {
                            Label("Cart (\(cartViewModel.itemCount))", systemImage: "cart.fill")
                        }
                        .help("Open cart")
                    }
                    Button {
                        selection = .profile
                    } label: {
                        BrandAvatar(size: 26)
                    }
                    .buttonStyle(.plain)
                    .help("Profile")
                }
            }
        }
        .task {
            if isAdmin {
                await modelsAdmin.refresh()
            }
        }
    }

    private func sidebarRow(title: String, systemName: String, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: systemName)
        }
        .tag(Optional(route))
    }

    private func dashboardRow(title: String, systemName: String, subtitle: String, route: HomeRoute) -> some View {
        Button {
            selection = route
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.appColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemName)
                        .foregroundStyle(Color.appColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.body())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                WelcomeHeader(
                    name: welcomeName,
                    subtitle: isAdmin
                        ? "Merchant desk · inventory, menu, models"
                        : "Guest desk · order and track pickups"
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.md),
                        GridItem(.flexible(), spacing: AppSpacing.md),
                        GridItem(.flexible(), spacing: AppSpacing.md),
                    ],
                    spacing: AppSpacing.md
                ) {
                    MetricTile(
                        title: "Menu live",
                        value: "\(availableMenuCount)",
                        systemName: "cup.and.saucer.fill"
                    )
                    MetricTile(
                        title: "Active orders",
                        value: "\(activeOrderCount)",
                        systemName: "tray.full.fill"
                    )
                    if isAdmin {
                        MetricTile(
                            title: "Low stock",
                            value: "\(lowStockCount)",
                            systemName: "shippingbox.fill"
                        )
                    } else {
                        MetricTile(
                            title: "All orders",
                            value: "\(orderViewModel.orders.count)",
                            systemName: "list.bullet"
                        )
                    }
                }

                if isAdmin {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        SectionHeader(title: "Operations", subtitle: "Keep the line moving")
                        VStack(spacing: 0) {
                            dashboardRow(
                                title: "Inventory",
                                systemName: inventoryIcon,
                                subtitle: "Adjust stock and review restock forecasts",
                                route: .inventory
                            )
                            Divider().padding(.leading, 56)
                            dashboardRow(
                                title: "Menu & pricing",
                                systemName: menuIcon,
                                subtitle: "Edit availability and prices",
                                route: .menuPricing
                            )
                            Divider().padding(.leading, 56)
                            dashboardRow(
                                title: "Models & training",
                                systemName: "cpu",
                                subtitle: "CoreML locally or ONNX on the API",
                                route: .models
                            )
                        }
                        .background(Color.surfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                                .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    SectionHeader(title: "Ordering", subtitle: "Guest pickup path")
                    VStack(spacing: 0) {
                        dashboardRow(
                            title: "Order",
                            systemName: cartFillIcon,
                            subtitle: cartViewModel.isEmpty
                                ? "Browse the board and build a cart"
                                : "\(cartViewModel.itemCount) in cart · continue checkout",
                            route: .orderNow
                        )
                        Divider().padding(.leading, 56)
                        dashboardRow(
                            title: "Orders",
                            systemName: trayFullFill,
                            subtitle: "Track status and cancel pending tickets",
                            route: .myOrders
                        )
                    }
                    .background(Color.surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                            .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.groupedBackgroundColor)
    }

    private func title(for route: HomeRoute) -> String {
        switch route {
        case .reservations: return "Reservations"
        case .peakTimes: return "Peak times"
        case .inventory: return "Inventory"
        case .team: return "Team"
        case .menuPricing: return "Menu & pricing"
        case .reports: return "Reports"
        case .models: return "Models & training"
        case .menu: return "Menu"
        case .orderNow: return "Order now"
        case .reserveTable: return "Reserve a table"
        case .myOrders: return "My orders"
        case .support: return "Support"
        case .profile: return "Profile"
        }
    }
}
#endif
