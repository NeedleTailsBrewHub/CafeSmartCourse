//
//  HomeView.swift
//  CafeSmartDev
//
//  Consumer home feed patterned after marketplace apps (Grubhub-style):
//  location header, search, category rail, promo, wide food cards, sections.
//

import SwiftUI

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
    @State var selectedTab: GuestTab = .home
    @State var homePath: [HomeRoute] = []
    @State var homeSearch = ""

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
    private let searchIcon = "android_note"
    private let pinIcon = "android_package"
#else
    private let cartFillIcon = "cart.fill"
    private let homeIcon = "house.fill"
    private let ordersIcon = "tray.full.fill"
    private let searchIcon = "magnifyingglass"
    private let pinIcon = "mappin.and.ellipse"
#endif

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                grubhubHome
                    .navigationBarTitleDisplayModeCompat()
                    .toolbar {
#if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                selectedTab = .profile
                            } label: {
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
            .tabItem { tabLabel("Profile", systemName: "person.crop.circle", androidName: "lock.fill") }
            .tag(GuestTab.profile)
        }
        .tint(Color.appColor)
    }

    private var grubhubHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Location + search chrome
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Button {
                        selectedTab = .order
                    } label: {
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

                // Category icon rail
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.md) {
                            ForEach(categories, id: \.self) { category in
                                Button {
                                    selectedTab = .order
                                } label: {
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

                // Active order tracker strip
                if activeOrderCount > 0 {
                    Button {
                        selectedTab = .orders
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Circle()
                                .fill(Color.appColor)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeOrderCount == 1 ? "1 order in progress" : "\(activeOrderCount) orders in progress")
                                    .font(AppFont.headline())
                                    .foregroundStyle(.primary)
                                Text("Track pickup status")
                                    .font(AppFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("View")
                                .font(AppFont.button())
                                .foregroundStyle(Color.appColor)
                        }
                        .padding(AppSpacing.md)
                        .background(Color.appColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)
                }

                // Promo banner carousel
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
                            colors: [Color.appAccentWarm, Color.appAccentWarm.opacity(0.75)]
                        ) {
                            selectedTab = .order
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .padding(.bottom, AppSpacing.lg)

                // Order again
                if !reorderNames.isEmpty {
                    homeSection(title: "Order again", actionTitle: "See all") {
                        selectedTab = .orders
                    } content: {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(reorderNames, id: \.self) { name in
                                    Button {
                                        selectedTab = .order
                                    } label: {
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

                // Popular near you style
                if !popularItems.isEmpty && homeSearch.isEmpty {
                    homeSection(title: "Popular right now", actionTitle: "See all") {
                        selectedTab = .order
                    } content: {
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

                // Vertical feed — Grubhub restaurant/item cards
                homeSection(
                    title: homeSearch.isEmpty ? "For you" : "Results",
                    actionTitle: homeSearch.isEmpty ? "See menu" : nil
                ) {
                    selectedTab = .order
                } content: {
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
                    .padding(.top, AppSpacing.lg)
                }

                Spacer(minLength: AppSpacing.xl)
            }
            .padding(.bottom, AppSpacing.lg)
        }
        .background(Color.backgroundColor)
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
    private func homeSection<Content: View>(
        title: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(title)
                    .font(AppFont.title2())
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.appColor)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            content()
        }
        .padding(.bottom, AppSpacing.lg)
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
}

// MARK: - Grubhub-style building blocks

struct PromoBannerCard: View {
    let title: String
    let subtitle: String
    let colors: [Color]
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppFont.title2())
                    .foregroundStyle(Color.appOnAccent)
                Text(subtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(Color.appOnAccent.opacity(0.92))
                Spacer(minLength: 0)
                Text("Order now")
                    .font(AppFont.button())
                    .foregroundStyle(colors.first ?? Color.appColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.appOnAccent)
                    .clipShape(Capsule())
            }
            .padding(AppSpacing.md)
            .frame(width: 280, height: 140, alignment: .leading)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

enum MarketplaceCardStyle {
    case compact
    case wide
}

struct MarketplaceFoodCard: View {
    let item: MenuItem
    var style: MarketplaceCardStyle = .wide
    var onTap: @MainActor () -> Void

    private var prepLabel: String {
        if let prep = item.prepSeconds, prep > 0 {
            return "\(max(1, prep / 60))–\(max(2, prep / 60 + 5)) min"
        }
        return "10–20 min"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: style == .wide ? 14 : 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.appColor.opacity(0.22),
                                    Color.appAccentWarm.opacity(0.28),
                                    Color.appColor.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: style == .wide ? 140 : 110)
                        .overlay {
                            MenuGlyph(category: item.category, size: style == .wide ? 64 : 52)
                        }

                    if style == .wide {
                        Text(CurrencyHelper.format(cents: item.priceCents))
                            .font(AppFont.footnote())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(AppFont.headline())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Pickup")
                            .font(AppFont.caption())
                            .foregroundStyle(Color.appColor)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(prepLabel)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                        if let category = item.category, !category.isEmpty {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(category)
                                .font(AppFont.caption())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if style == .compact {
                        Text(CurrencyHelper.format(cents: item.priceCents))
                            .font(AppFont.callout())
                            .foregroundStyle(Color.appColor)
                    } else if let desc = item.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, style == .wide ? 2 : 0)
                .padding(.top, 10)
            }
            .frame(width: style == .compact ? 220 : nil, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(CurrencyHelper.format(cents: item.priceCents)), \(prepLabel)")
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

enum HomeRoute: Hashable {
    case reservations
    case peakTimes
    case inventory
    case team
    case menuPricing
    case reports
    case models
    case menu
    case orderNow
    case reserveTable
    case myOrders
    case support
    case profile
}

struct DestinationView: View {
    let route: HomeRoute
    var body: some View {
        switch route {
        case .profile:
            ProfileView()
        case .inventory:
            InventoryView()
        case .menuPricing:
            MenuPricingView()
        case .menu, .orderNow:
            OrderFlowView()
        case .myOrders:
            MyOrdersView()
        case .models:
            #if os(macOS)
            ModelsAdminView()
            #else
            EmptyState(
                title: "Models on Mac",
                subtitle: "Train and activate restock models from the Mac desk."
            )
            #endif
        case .reservations, .peakTimes, .team, .reports, .reserveTable, .support:
            EmptyState(
                title: "Coming soon",
                subtitle: "This workspace isn’t available in this build."
            )
        }
    }
}

struct MerchantControlsSection: View {
    var onSelect: @MainActor (HomeRoute) -> Void

#if os(Android)
    let inventoryIcon = "android_package"
    let menuIcon = "android_note"
#else
    let inventoryIcon = "shippingbox.fill"
    let menuIcon = "square.and.pencil"
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(title: "Operations", subtitle: "Merchant tools")
            QuickActionList(
                items: [
                    .init(
                        title: "Inventory",
                        subtitle: "Counts, storage, restock signals",
                        systemName: inventoryIcon,
                        route: .inventory
                    ),
                    .init(
                        title: "Menu & pricing",
                        subtitle: "Names, prices, availability",
                        systemName: menuIcon,
                        route: .menuPricing
                    ),
                ]
            ) { item in
                onSelect(item.route)
            }
        }
    }
}
