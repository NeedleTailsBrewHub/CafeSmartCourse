//
//  HomeView.swift
//  CafeSmart
//
//  Grubhub-style consumer home: pickup header, search, categories, promo,
//  popular/for-you food cards, plus merchant tools for admins.
//

import SwiftUI
import VenueSmartKit

enum GuestTab: Hashable {
    case home
    case order
    case orders
    case profile
}

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var selectedTab: GuestTab = .home
    @State var homePath: [HomeRoute] = []
    @State var homeSearch = ""
    @State var serverTrainingAvailable = false
    @State var isTraining = false

    private var isAdmin: Bool {
        authenticationViewModel.user?.isAdmin ?? false
    }

    private var welcomeName: String {
        let raw = authenticationViewModel.user?.name
            ?? authenticationViewModel.user?.email
            ?? "there"
        if let at = raw.firstIndex(of: "@") {
            return String(raw[..<at])
        }
        return raw
    }

    private var availableItems: [MenuItem] {
        menuViewModel.items.filter(\.isAvailable)
    }

    private var categories: [String] {
        Array(Set(availableItems.compactMap(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var popularItems: [MenuItem] {
        Array(availableItems.prefix(10))
    }

    private var forYouItems: [MenuItem] {
        let query = homeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = availableItems
        guard !query.isEmpty else { return Array(base.prefix(12)) }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var reorderNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for order in orderViewModel.orders.reversed() {
            for item in order.items {
                guard let name = item.name, seen.insert(name).inserted else { continue }
                names.append(name)
                if names.count >= 6 { return names }
            }
        }
        return names
    }

    private var activeOrderCount: Int {
        orderViewModel.orders.filter {
            $0.status == .pending || $0.status == .preparing || $0.status == .ready
        }.count
    }

#if os(Android)
    private let cartFillIcon = "orders"
    private let homeIcon = "android_coffee_cup"
    private let ordersIcon = "orders"
    private let searchIcon = "android_tag"
    private let pinIcon = "android_package"
    private let reserveIcon = "android_calendar"
#else
    private let cartFillIcon = "cart.fill"
    private let homeIcon = "house.fill"
    private let ordersIcon = "tray.full.fill"
    private let searchIcon = "magnifyingglass"
    private let pinIcon = "mappin.and.ellipse"
    private let reserveIcon = "calendar"
#endif

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                grubhubHome
                    .navigationBarTitleDisplayModeCompat()
                    .toolbar {
#if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { selectedTab = .profile } label: {
                                BrandAvatar(size: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Profile")
                        }
#endif
                    }
                    .navigationDestination(for: HomeRoute.self) { route in
                        DestinationView(route: route)
                    }
                    .task {
                        await refreshMenuIfNeeded()
                        await refreshTrainCapabilities()
                        if orderViewModel.orders.isEmpty {
                            try? await orderViewModel.fetchOrders(reset: true, scope: .mine)
                        }
                    }
                    .onChange(of: homePath) { _, _ in
                        appNotificationCenter.hide()
                    }
            }
            .tabItem { tabLabel("Home", systemName: "house.fill", androidName: homeIcon) }
            .tag(GuestTab.home)

            NavigationStack {
                OrderFlowView()
            }
            .tabItem { tabLabel("Order", systemName: "cart.fill", androidName: cartFillIcon) }
            .badge(cartViewModel.itemCount)
            .tag(GuestTab.order)

            NavigationStack {
                MyOrdersView(onStartOrder: { selectedTab = .order })
            }
            .tabItem { tabLabel("Orders", systemName: "tray.full.fill", androidName: ordersIcon) }
            .badge(activeOrderCount)
            .tag(GuestTab.orders)

            NavigationStack {
                ProfileView()
            }
            .tabItem { tabLabel("Settings", systemName: "gearshape.fill", androidName: "lock.fill") }
            .tag(GuestTab.profile)
        }
        .tint(Color.appColor)
    }

    private var grubhubHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Button { selectedTab = .order } label: {
                        HStack(spacing: 6) {
                            AppImage(name: pinIcon)
                                .foregroundStyle(Color.appColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Pickup")
                                    .font(AppFont.caption())
                                    .foregroundStyle(.secondary)
                                Text("CaféSmart · Counter")
                                    .font(AppFont.headline())
                                    .foregroundStyle(.primary)
                            }
#if os(Android)
                            Text("▾")
                                .font(AppFont.caption())
                                .foregroundStyle(.secondary)
#else
                            AppImage(name: "chevron.down")
                                .font(AppFont.caption())
                                .foregroundStyle(.secondary)
#endif
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    AppTextField(
                        placeholder: "Search coffee, food, and more",
                        text: $homeSearch,
                        leadingSystemImage: searchIcon
                    )
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)

                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.md) {
                            ForEach(categories, id: \.self) { category in
                                Button { selectedTab = .order } label: {
                                    VStack(spacing: 8) {
                                        MenuGlyph(category: category, size: 56)
                                            .clipShape(Circle())
                                        Text(category)
                                            .font(AppFont.caption())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                    .padding(.bottom, AppSpacing.md)
                }

                if activeOrderCount > 0 {
                    LiveStatusBanner(
                        title: activeOrderCount == 1
                            ? "1 order in progress"
                            : "\(activeOrderCount) orders in progress",
                        subtitle: "Track pickup status"
                    ) {
                        selectedTab = .orders
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        PromoBannerCard(
                            title: "Order ahead",
                            subtitle: "Skip the line · pay at pickup",
                            colors: [Color.appColor, Color.appColor.opacity(0.75)]
                        ) {
                            selectedTab = .order
                        }
                        PromoBannerCard(
                            title: "Hi, \(welcomeName)",
                            subtitle: cartViewModel.isEmpty
                                ? "What are you craving?"
                                : "\(cartViewModel.itemCount) waiting in your cart",
                            colors: [Color.appAccentWarm, Color.appAccentWarm.opacity(0.8)]
                        ) {
                            selectedTab = .order
                        }
                        PromoBannerCard(
                            title: "Reserve a table",
                            subtitle: "Book seating for later today",
                            colors: [
                                Color.appAccentWarm.opacity(0.95),
                                Color.appColor.opacity(0.85),
                            ],
                            ctaTitle: "Book now"
                        ) {
                            homePath.append(.reserveTable)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .padding(.bottom, AppSpacing.lg)

                MarketplaceSection(title: "Quick actions", edgeBleed: true) {
                    QuickActionList(
                        items: [
                            .init(
                                title: "Reserve a table",
                                subtitle: "Pick a time and party size",
                                systemName: reserveIcon,
                                route: .reserveTable),
                            .init(
                                title: "Order now",
                                subtitle: "Browse the menu and checkout",
                                systemName: cartFillIcon,
                                route: .orderNow),
                        ]
                    ) { item in
                        if item.route == .orderNow {
                            selectedTab = .order
                        } else {
                            homePath.append(item.route)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                if !reorderNames.isEmpty {
                    MarketplaceSection(
                        title: "Order again",
                        actionTitle: "See all",
                        edgeBleed: true,
                        action: { selectedTab = .orders }
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(reorderNames, id: \.self) { name in
                                    Button { selectedTab = .order } label: {
                                        HStack(spacing: AppSpacing.sm) {
                                            MenuGlyph(category: name, size: 40)
                                            Text(name)
                                                .font(AppFont.footnote())
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                                .frame(maxWidth: 96, alignment: .leading)
                                        }
                                        .padding(10)
                                        .background(Color.surfaceColor)
                                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                                                .strokeBorder(Color.separatorColor.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }

                if !popularItems.isEmpty && homeSearch.isEmpty {
                    MarketplaceSection(
                        title: "Popular right now",
                        actionTitle: "See all",
                        edgeBleed: true,
                        action: { selectedTab = .order }
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.md) {
                                ForEach(popularItems) { item in
                                    MarketplaceFoodCard(item: item, style: .compact) {
                                        selectedTab = .order
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }

                MarketplaceSection(
                    title: homeSearch.isEmpty ? "For you" : "Results",
                    actionTitle: homeSearch.isEmpty ? "See menu" : nil,
                    edgeBleed: true,
                    action: homeSearch.isEmpty ? { selectedTab = .order } : nil
                ) {
                    LazyVStack(spacing: AppSpacing.md) {
                        if forYouItems.isEmpty {
                            EmptyState(
                                title: "No matches",
                                subtitle: "Try another search or browse the full menu.",
                                actionTitle: "Browse menu",
                                action: { selectedTab = .order }
                            )
                            .padding(.horizontal, AppSpacing.lg)
                        } else {
                            ForEach(forYouItems) { item in
                                MarketplaceFoodCard(item: item, style: .wide) {
                                    selectedTab = .order
                                }
                                .padding(.horizontal, AppSpacing.lg)
                            }
                        }
                    }
                }

                if isAdmin {
                    MerchantControlsSection { route in
                        homePath.append(route)
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    PrimaryButton(title: isTraining ? "Training…" : "Train on server") {
                        Task { await trainOnServer() }
                    }
                    .disabled(!serverTrainingAvailable || isTraining)
                    .opacity(serverTrainingAvailable ? 1 : 0.5)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)

                    if !serverTrainingAvailable {
                        Text("Server training unavailable (API capabilities).")
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                }

                Spacer(minLength: AppSpacing.xl)
            }
            .padding(.bottom, AppSpacing.lg)
        }
        .background(Color.groupedBackgroundColor)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .principal) {
                Text("CaféSmart")
                    .font(AppFont.headline())
            }
#endif
        }
    }

    @ViewBuilder
    private func tabLabel(_ title: String, systemName: String, androidName: String) -> some View {
#if os(Android)
        Label {
            Text(title)
        } icon: {
            AppImage(name: androidName)
        }
#else
        Label(title, systemImage: systemName)
#endif
    }

    @MainActor
    private func refreshMenuIfNeeded() async {
        guard menuViewModel.items.isEmpty else { return }
        menuViewModel.filterAvailable = true
        do {
            try await menuViewModel.fetchMenu(reset: true)
        } catch {
            logger.info("Home menu prefetch failed: \(error)")
        }
    }

    @MainActor
    private func refreshTrainCapabilities() async {
        guard isAdmin else {
            serverTrainingAvailable = false
            return
        }
        do {
            let caps = try await AIService.shared.fetchCapabilities()
            serverTrainingAvailable = caps.serverTraining
        } catch {
            serverTrainingAvailable = false
        }
    }

    @MainActor
    private func trainOnServer() async {
        guard !isTraining else { return }
        isTraining = true
        defer { isTraining = false }
        do {
            let message = try await AIService.shared.trainRestockOnServer()
            appNotificationCenter.show(message, iconSystemName: "checkmark.circle.fill", duration: 3.0)
        } catch {
            let detail = error.localizedDescription
            let banner = detail.localizedCaseInsensitiveContains("unavailable") || detail.contains("503")
                ? "Server training unavailable (503)."
                : "Training failed: \(detail)"
            appNotificationCenter.show(banner, iconSystemName: "xmark.octagon.fill", duration: 4.0)
        }
    }
}

extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeCompat() -> some View {
#if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

// MARK: - Sections
// Routing uses kit DestinationView + MerchantGuestDestinations (injected in CafeSmartApp).

struct MerchantControlsSection: View {
    var onSelect: @MainActor (HomeRoute) -> Void

#if os(Android)
    let reservationIcon = "android_calendar"
    let inventoryIcon = "android_package"
    let menuIcon = "android_note"
    let tagsIcon = "android_tag"
    let ordersIcon = "orders"
    let teamIcon = "android_group"
    let loyaltyIcon = "android_coffee_cup"
    let reportsIcon = "bars_time"
#else
    let reservationIcon = "calendar.badge.clock"
    let inventoryIcon = "shippingbox.fill"
    let menuIcon = "square.and.pencil"
    let tagsIcon = "tag.fill"
    let ordersIcon = "list.bullet.rectangle"
    let teamIcon = "person.2.fill"
    let loyaltyIcon = "star.fill"
    let reportsIcon = "chart.bar.fill"
#endif

    var body: some View {
        MarketplaceSection(title: "Merchant tools") {
            QuickActionList(
                items: [
                    .init(title: "Orders board", subtitle: "Live ticket queue", systemName: ordersIcon, route: .ordersBoard),
                    .init(title: "Reservations", subtitle: "Tables and seating", systemName: reservationIcon, route: .reservations),
                    .init(title: "Inventory", subtitle: "Stock, tags, and CSV", systemName: inventoryIcon, route: .inventory),
                    .init(title: "Menu pricing", subtitle: "Edit items and availability", systemName: menuIcon, route: .menuPricing),
                    .init(title: "Tags", subtitle: "Allergens and dietary labels", systemName: tagsIcon, route: .tags),
                    .init(title: "Seating", subtitle: "Areas and tables", systemName: "chair.lounge.fill", route: .seating),
                    .init(title: "Recipes", subtitle: "Menu → inventory links", systemName: "list.bullet.clipboard.fill", route: .recipes),
                    .init(title: "Team", subtitle: "Who’s on shift", systemName: teamIcon, route: .team),
                    .init(title: "Rewards & payments", subtitle: "Program, in-app checkout, and guest points", systemName: loyaltyIcon, route: .rewards),
                    .init(title: "Support desk", subtitle: "Guest help tickets", systemName: "bubble.left.and.bubble.right.fill", route: .supportDesk),
                    .init(title: "Reports", subtitle: "Today’s floor snapshot", systemName: reportsIcon, route: .reports),
                ]
            ) { item in onSelect(item.route) }
        }
    }
}
