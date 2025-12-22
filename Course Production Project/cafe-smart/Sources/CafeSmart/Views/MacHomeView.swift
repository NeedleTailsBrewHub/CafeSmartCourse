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
import BSON

struct MacHomeView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(SocketReceiver.self) var socketReceiver
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var selection: HomeRoute? = nil
    @State var notificationText = ""
    
    private var isAdmin: Bool {
        authenticationViewModel.user?.isAdmin ?? false
    }

    private var welcomeName: String {
        authenticationViewModel.user?.name
        ?? authenticationViewModel.user?.email
        ?? "Friend"
    }

    private var reservationIcon: String { "calendar.badge.clock" }
    private var peakTimeIcon: String { "chart.bar.fill" }
    private var inventoryIcon: String { "shippingbox.fill" }
    private var teamIcon: String { "person.2.fill" }
    private var menuIcon: String { "square.and.pencil" }
    private var reportsIcon: String { "doc.text.magnifyingglass" }
    private var cartFillIcon: String { "cart.fill" }
    private var calendarIcon: String { "calendar" }
    private var trayFullFill: String { "tray.full.fill" }
    private var questionMarkCircleFill: String { "questionmark.circle.fill" }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Overview") {
                    Button {
                        selection = nil
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    .buttonStyle(.plain)
                }
                Section("Merchant console") {
                    sidebarRow(title: "Reservations", systemName: reservationIcon, route: .reservations)
                    sidebarRow(title: "Peak times", systemName: peakTimeIcon, route: .peakTimes)
                    sidebarRow(title: "Inventory", systemName: inventoryIcon, route: .inventory)
                    sidebarRow(title: "Team", systemName: teamIcon, route: .team)
                    sidebarRow(title: "Menu & pricing", systemName: menuIcon, route: .menuPricing)
                    sidebarRow(title: "Reports", systemName: reportsIcon, route: .reports)
                }
                Section("Ordering & reservations") {
                    sidebarRow(title: "Order now", systemName: cartFillIcon, route: .orderNow)
                    sidebarRow(title: "Reserve a table", systemName: calendarIcon, route: .reserveTable)
                    sidebarRow(title: "My orders", systemName: trayFullFill, route: .myOrders)
                    sidebarRow(title: "Help & support", systemName: questionMarkCircleFill, route: .support)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("CafeSmart")
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
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        selection = nil
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    if isAdmin {
                        Button {
                            Task.detached {
                                let service = try await MLService()
                                await service.startTraining()
                            }
                        } label: {
                            Label("Train Data", systemImage: "bolt.badge.a.fill")
                        }
                    }
                    Button {
                        selection = .profile
                    } label: {
                        Image("Logo", bundle: .module)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }


        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private func sidebarRow(title: String, systemName: String, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: systemName)
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Welcome back").font(AppFont.footnote()).foregroundStyle(.secondary)
                        Text(welcomeName).font(AppFont.title()).lineLimit(1)
                        Text("Dashboard overview").font(AppFont.subheadline()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image("Logo", bundle: .module)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.appColor.opacity(0.2), lineWidth: 1))
                }

                if isAdmin {
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
                    ) { item in selection = item.route }
                    Divider()
                }

                CustomerControlsSection { route in selection = route }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
        }
        .background(Color.backgroundColor)
    }

    private func title(for route: HomeRoute) -> String {
        switch route {
        case .reservations: return "Reservations"
        case .peakTimes: return "Peak times"
        case .inventory: return "Inventory"
        case .team: return "Team"
        case .menuPricing: return "Menu & pricing"
        case .reports: return "Reports"
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


