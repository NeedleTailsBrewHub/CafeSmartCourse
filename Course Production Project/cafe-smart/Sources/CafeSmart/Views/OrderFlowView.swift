//
//  OrderFlowView.swift
//  CafeSmart
//
//  Marketplace-style menu: sticky cart, dense rows, checkout review.
//

import SwiftUI
#if canImport(SkipStripe) && !os(macOS)
import SkipStripe
#endif
import VenueSmartKit

struct OrderFlowView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(TagViewModel.self) var tagViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(BusinessViewModel.self) var businessViewModel
    /// Optional item to open customize / add when deep-linked.
    var prefillItem: MenuItem? = nil
    @State var itemToCustomize: MenuItem? = nil
    @State var isSubmitting = false
    @State var pickupASAP = true
    @State var pickupTime = Date().addingTimeInterval(20 * 60)
    @State var didApplyPrefill = false
    @State var selectedCategory: String? = nil
    @State var placedOrderId: String?
    @State var showsReview = false
    @State var searchTask: Task<Void, Never>?
    @State var useLoyaltyPoints = false
    @State var loyalty = LoyaltyViewModel()
    @State var checkoutCapabilities: CheckoutCapabilities?
    @State var paymentPhase: CheckoutPaymentPhase = .idle
    @State var pendingCheckoutSessionId: String?
    @State var stripeSheetFields: StripeSheetConfigFields?

#if os(Android)
    let minusIcon = "android_minus"
    let plusIcon = "android_plus"
    let trashIcon = "android_archive"
    let searchIcon = "android_tag"
    let successIcon = "orders"
#else
    let minusIcon = "minus"
    let plusIcon = "plus"
    let trashIcon = "trash"
    let searchIcon = "magnifyingglass"
    let successIcon = "checkmark.circle.fill"
#endif

    private var items: [MenuItem] {
        menuViewModel.items.filter { $0.isAvailable }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { menuViewModel.searchQuery },
            set: { menuViewModel.searchQuery = $0 }
        )
    }

    private var searchActive: Bool {
        !menuViewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categories: [String] {
        Array(
            Set(
                items.compactMap { item -> String? in
                    guard let c = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else {
                        return nil
                    }
                    return c
                }
            )
        ).sorted()
    }

    private var filteredItems: [MenuItem] {
        if let selectedCategory {
            return items.filter {
                ($0.category ?? "").caseInsensitiveCompare(selectedCategory) == .orderedSame
            }
        }
        return items
    }

    private var featuredItems: [MenuItem] {
        var seen = Set<String>()
        var picks: [MenuItem] = []
        for item in items {
            let key = item.category ?? item.id
            if seen.insert(key).inserted {
                picks.append(item)
            }
            if picks.count >= 6 { break }
        }
        if picks.count < 3 {
            return Array(items.prefix(6))
        }
        return picks
    }

    private var groupedItems: [(category: String, items: [MenuItem])] {
        let source = filteredItems
        var order: [String] = []
        var map: [String: [MenuItem]] = [:]
        for item in source {
            let key = item.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Other"
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key]?.append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
#if os(macOS)
        macBody
#else
        phoneBody
#endif
    }

    private var phoneBody: some View {
        phoneMenuCanvas
            .safeAreaInset(edge: .bottom) {
                if !cartViewModel.isEmpty {
                    CartSummaryBar(
                        itemCount: cartViewModel.itemCount,
                        totalCents: cartViewModel.totalCents
                    ) {
                        showsReview = true
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .background(.ultraThinMaterial)
                }
            }
            .modifier(lifecycleModifier)
    }

#if os(macOS)
    private var macMenuColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 168, maximum: 200), spacing: AppSpacing.md)]
    }

    private var macBody: some View {
        HSplitView {
            CMSWorkspace(maxContentWidth: nil) {
                HStack(spacing: 6) {
                    Text("Pickup")
                        .font(AppFont.caption())
                        .foregroundStyle(Color.appColor)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("CaféSmart · Counter")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                menuHeader
                if menuViewModel.catalogNeedsRefresh {
                    CatalogStaleBanner {
                        Task { await reloadMenu() }
                    }
                }
                if let err = orderViewModel.errorMessage, !err.isEmpty {
                    ErrorBanner(message: err)
                }
                macMenuGrid
            }
            .frame(minWidth: 0, idealWidth: 480)
            .layoutPriority(1)
            .navigationTitle("Order")

            cartSidebar
                .frame(
                    minWidth: cartViewModel.isEmpty ? 240 : 360,
                    idealWidth: cartViewModel.isEmpty ? 280 : 400,
                    maxWidth: 480
                )
        }
        .background(Color.groupedBackgroundColor)
        .modifier(lifecycleModifier)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !cartViewModel.isEmpty {
                    Text("\(cartViewModel.itemCount) in cart")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await reloadMenu() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh menu")
            }
        }
    }

    @ViewBuilder
    private var macMenuGrid: some View {
        if menuViewModel.isLoading && items.isEmpty {
            LoadingBlock()
        } else if items.isEmpty {
            EmptyState(
                title: "No menu items",
                subtitle: "Pull to refresh once the menu is available."
            )
        } else if filteredItems.isEmpty {
            EmptyState(
                title: "No matches",
                subtitle: searchActive ? "Nothing matched that search." : "Try another category."
            )
        } else {
            if !searchActive && selectedCategory == nil && !featuredItems.isEmpty {
                MarketplaceSection(title: "Popular right now") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.md) {
                            ForEach(featuredItems) { item in
                                MarketplaceFoodCard(
                                    item: item,
                                    style: .compact,
                                    showsAdd: true,
                                    compactWidth: 180
                                ) {
                                    handleAdd(item)
                                }
                            }
                        }
                    }
                }
            }
            ForEach(groupedItems, id: \.category) { group in
                MarketplaceSection(title: selectedCategory == nil ? group.category : "Menu") {
                    LazyVGrid(columns: macMenuColumns, spacing: AppSpacing.md) {
                        ForEach(group.items) { item in
                            MarketplaceFoodCard(
                                item: item,
                                style: .compact,
                                showsAdd: true,
                                compactWidth: 168
                            ) {
                                handleAdd(item)
                            }
                        }
                    }
                }
            }
            if menuViewModel.hasMore {
                SecondaryButton(
                    title: menuViewModel.isLoadingMore ? "Loading…" : "Load more",
                    fillWidth: false
                ) {
                    Task { await loadMore() }
                }
                .disabled(menuViewModel.isLoadingMore)
            }
        }
    }

    private var cartSidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Your cart")
                .font(AppFont.title2())
            Text(
                cartViewModel.isEmpty
                    ? "Add items from the menu"
                    : "\(cartViewModel.itemCount) item\(cartViewModel.itemCount == 1 ? "" : "s")"
            )
            .font(AppFont.caption())
            .foregroundStyle(.secondary)
            if cartViewModel.isEmpty {
                EmptyState(
                    title: "Cart is empty",
                    subtitle: "Choose something from today’s board."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(cartViewModel.lines) { line in
                            cartLineRow(line)
                        }
                    }
                }
                SurfacePanel {
                    HStack {
                        Text("Total")
                            .font(AppFont.headline())
                        Spacer()
                        Text(
                            CurrencyHelper.dollars(fromCents: cartViewModel.totalCents),
                            format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                        )
                        .font(AppFont.title2())
                        .foregroundStyle(Color.appColor)
                    }
                }
                PrimaryButton(
                    title: isSubmitting ? "Placing…" : "Review & place order",
                    fillWidth: true
                ) {
                    showsReview = true
                }
                .disabled(isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.surfaceColor)
    }

    private func cartLineRow(_ line: CartLine) -> some View {
        SurfacePanel {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                MenuGlyph(category: line.item.category, imageURL: line.item.imageURL, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.item.name)
                        .font(AppFont.body())
                    if let sizeName = line.sizeName, !sizeName.isEmpty {
                        Text(sizeName)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    StepperChips(
                        minusIcon: minusIcon,
                        plusIcon: plusIcon,
                        valueLabel: "\(line.quantity)",
                        onMinus: { cartViewModel.decrement(line) },
                        onPlus: { cartViewModel.increment(line) }
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                    Text(
                        CurrencyHelper.dollars(fromCents: line.lineCents),
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .font(AppFont.callout())
                    Button(role: .destructive) {
                        cartViewModel.remove(line)
                    } label: {
                        AppImage(name: trashIcon)
                            .foregroundStyle(Color.appDanger)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(line.item.name)")
                }
            }
        }
    }
#endif

    private var phoneMenuCanvas: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: 6) {
                    Text("Pickup")
                        .font(AppFont.caption())
                        .foregroundStyle(Color.appColor)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("CaféSmart · Counter")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Menu")
                    .font(AppFont.title2())
                Text(searchActive
                     ? "Searching the café menu"
                     : "Skip the line · pay at the counter")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                AppTextField(
                    placeholder: "Search coffee, food, and more",
                    text: searchBinding,
                    leadingSystemImage: searchIcon
                )

                if menuViewModel.catalogNeedsRefresh {
                    CatalogStaleBanner {
                        Task { await reloadMenu() }
                    }
                }

                if !categories.isEmpty && !searchActive {
                    CategoryChipBar(categories: categories, selection: $selectedCategory)
                } else if searchActive {
                    Text("\(filteredItems.count) match\(filteredItems.count == 1 ? "" : "es")")
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.appColor)
                }

                if let placedOrderId {
                    StatusChip(text: "Order #\(placedOrderId.prefix(6)) placed", tone: .success)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
            .background(Color.groupedBackgroundColor)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if let err = orderViewModel.errorMessage, !err.isEmpty {
                        ErrorBanner(message: err)
                    }
                    menuContent
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, cartViewModel.isEmpty ? AppSpacing.lg : 88)
                .padding(.top, AppSpacing.sm)
            }
            .background(Color.groupedBackgroundColor)
        }
        .navigationTitle("Order")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    private var menuHeader: some View {
        Text("Today’s board")
            .font(AppFont.title2())
        Text(
            searchActive
                ? "Searching the café menu"
                : "Search, customize, and send for pickup"
        )
        .font(AppFont.caption())
        .foregroundStyle(.secondary)
        AppTextField(
            placeholder: "Search coffee, food, and more",
            text: searchBinding,
            leadingSystemImage: searchIcon
        )
        if !categories.isEmpty && !searchActive {
            CategoryChipBar(categories: categories, selection: $selectedCategory)
        }
        if let placedOrderId {
            StatusChip(text: "Order #\(placedOrderId.prefix(6)) placed", tone: .success)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if menuViewModel.isLoading && items.isEmpty {
            LoadingBlock()
        } else if items.isEmpty {
            EmptyState(
                title: "No menu items",
                subtitle: "Pull to refresh once the menu is available."
            )
        } else if filteredItems.isEmpty {
            EmptyState(
                title: "No matches",
                subtitle: searchActive
                    ? "Nothing matched that search."
                    : "Try another category."
            )
        } else {
            if !searchActive && selectedCategory == nil && !featuredItems.isEmpty {
                MarketplaceSection(title: "Popular right now") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.md) {
                            ForEach(featuredItems) { item in
                                MarketplaceFoodCard(item: item, style: .compact, showsAdd: true) {
                                    handleAdd(item)
                                }
                            }
                        }
                    }
                }
            }

            LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(groupedItems, id: \.category) { group in
                    MarketplaceSection(title: selectedCategory == nil ? group.category : "Results") {
                        SurfacePanel(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    MenuOrderRow(
                                        item: item,
                                        tagLine: tagLine(for: item),
                                        showsAdd: true
                                    ) {
                                        handleAdd(item)
                                    }
                                    if index < group.items.count - 1 {
                                        Divider().padding(.leading, 88)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if menuViewModel.hasMore {
                SecondaryButton(
                    title: menuViewModel.isLoadingMore ? "Loading…" : "Load more",
                    fillWidth: true
                ) {
                    Task { await loadMore() }
                }
                .disabled(menuViewModel.isLoadingMore)
            }
        }
    }

    private var loyaltyQuote: LoyaltyCheckoutQuote {
        LoyaltyCheckoutQuote.quote(
            lines: cartViewModel.lines,
            balance: loyalty.account?.points ?? 0,
            earnPerUnit: businessViewModel.config?.earnPointsPerUnit ?? 5,
            programEnabled: businessViewModel.config?.isLoyaltyProgramEnabled == true,
            usePoints: useLoyaltyPoints)
    }

    private var lifecycleModifier: OrderFlowLifecycle {
        OrderFlowLifecycle(
            itemToCustomize: $itemToCustomize,
            showsReview: $showsReview,
            pickupASAP: $pickupASAP,
            pickupTime: $pickupTime,
            isSubmitting: $isSubmitting,
            placedOrderId: $placedOrderId,
            searchTask: $searchTask,
            useLoyaltyPoints: $useLoyaltyPoints,
            paymentPhase: $paymentPhase,
            stripeSheetFields: $stripeSheetFields,
            pendingCheckoutSessionId: $pendingCheckoutSessionId,
            loyaltyQuote: loyaltyQuote,
            pointsBalance: loyalty.account?.points ?? 0,
            programEnabled: businessViewModel.config?.isLoyaltyProgramEnabled == true,
            showPayNow: showPayNowCTA,
            showPayAtPickup: showPayAtPickupCTA,
            onAppearPrefill: applyPrefillIfNeeded,
            reloadMenu: reloadMenu,
            loadLoyaltyContext: {
                if businessViewModel.config == nil {
                    try? await businessViewModel.fetchConfig()
                }
                if let id = authenticationViewModel.user?.id {
                    await loyalty.fetchLoyalty(userId: id)
                }
                await refreshCheckoutCapabilities()
            },
            checkout: checkout,
            preparePayNow: preparePayNow,
            confirmPrepaid: confirmPrepaid
        )
    }

    private func tagLine(for item: MenuItem) -> String? {
        let groups = tagViewModel.labelsByGroup(tagIds: item.tagIds)
        let names = groups.flatMap(\.tags)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    @MainActor
    private func handleAdd(_ item: MenuItem) {
        placedOrderId = nil
        if let opts = item.sizeOptions, !opts.isEmpty {
            itemToCustomize = item
        } else {
            cartViewModel.add(item: item)
            appNotificationCenter.show(
                "\(item.name) added",
                iconSystemName: successIcon,
                duration: 1.8
            )
        }
    }
}

extension OrderFlowView {
    @MainActor
    private func reloadMenu() async {
        do {
            try await menuViewModel.fetchMenu(reset: true)
            orderViewModel.errorMessage = nil
        } catch {
            if RequestCancellation.isCancellation(error) { return }
            orderViewModel.errorMessage = "Failed to load menu."
        }
    }

    @MainActor
    private func loadMore() async {
        do {
            try await menuViewModel.loadMore()
        } catch {
            if RequestCancellation.isCancellation(error) { return }
            orderViewModel.errorMessage = "Failed to load more menu items."
        }
    }

    @MainActor private func checkout() async {
        guard !cartViewModel.isEmpty, !isSubmitting else { return }
        guard showPayAtPickupCTA else {
            orderViewModel.errorMessage = "Pay at pickup is off. Use Pay now."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let request = CreateOrderRequest(
            customerName: authenticationViewModel.user?.name ?? authenticationViewModel.user?.email ?? "",
            items: cartOrderItems,
            pickupTime: pickupASAP ? nil : pickupTime,
            channel: .pickup,
            serviceType: .barista,
            tableId: nil,
            guests: nil,
            reservationId: nil,
            useLoyaltyPoints: useLoyaltyPoints,
            paymentMode: .payAtPickup)
        do {
            let order = try await orderViewModel.createOrder(request)
            await finishCheckoutSuccess(order)
        } catch {
            paymentPhase = .failed
            if case Errors.failedRequest(let code) = error {
                orderViewModel.errorMessage = "Checkout failed (\(code)). Please try again."
            } else {
                orderViewModel.errorMessage = "Checkout failed. Please try again."
            }
            logger.error("Checkout failed: \(String(describing: error))")
        }
    }

    private var cartOrderItems: [OrderItem] {
        cartViewModel.lines.map { line in
            var parts: [String] = []
            if let sizeName = line.sizeName, !sizeName.isEmpty {
                let delta = CurrencyHelper.format(cents: line.sizeDeltaCents)
                parts.append("Size: \(sizeName) (+\(delta))")
            }
            parts.append("qty=\(line.quantity)")
            return OrderItem(
                menuItemId: line.item.id,
                name: line.item.name,
                quantity: line.quantity,
                notes: parts.joined(separator: " · "),
                unitPriceCents: line.item.priceCents + line.sizeDeltaCents,
                sizeName: line.sizeName)
        }
    }

#if os(macOS)
    private var isMacCheckout: Bool { true }
#else
    private var isMacCheckout: Bool { false }
#endif

    private var showPayNowCTA: Bool {
        CheckoutPaymentCoordinator.showsPayNow(
            prepaidEnabled: checkoutCapabilities?.prepaidEnabled == true,
            isMac: isMacCheckout)
    }

    private var showPayAtPickupCTA: Bool {
        CheckoutPaymentCoordinator.showsPayAtPickup(
            payAtPickupEnabled: checkoutCapabilities?.isPayAtPickupEnabled ?? true)
    }

    @MainActor
    private func refreshCheckoutCapabilities() async {
        do {
            checkoutCapabilities = try await orderViewModel.fetchCheckoutCapabilities()
        } catch {
            checkoutCapabilities = CheckoutCapabilities(
                prepaidAvailable: false,
                prepaidEnabled: false,
                payAtPickupEnabled: true)
        }
    }

    @MainActor
    private func preparePayNow() async {
        guard !cartViewModel.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        paymentPhase = .preparing
        stripeSheetFields = nil
        pendingCheckoutSessionId = nil
        orderViewModel.errorMessage = nil
        defer { isSubmitting = false }
        let request = CreateCheckoutSessionRequest(
            customerName: authenticationViewModel.user?.name ?? authenticationViewModel.user?.email ?? "",
            items: cartOrderItems,
            pickupTime: pickupASAP ? nil : pickupTime,
            channel: .pickup,
            serviceType: .barista,
            useLoyaltyPoints: useLoyaltyPoints)
        do {
            let session = try await orderViewModel.prepareCheckout(request)
            pendingCheckoutSessionId = session.sessionId
            let phase = CheckoutPaymentCoordinator.phaseAfterPrepare(response: session)
            paymentPhase = phase
            if phase == .confirming {
                await confirmPrepaid(sessionId: session.sessionId)
            } else if let fields = CheckoutPaymentCoordinator.sheetConfig(from: session) {
                stripeSheetFields = fields
            } else {
                paymentPhase = .failed
                orderViewModel.errorMessage = "Could not start card payment. Try pay at pickup."
            }
        } catch {
            paymentPhase = .failed
            if case Errors.failedRequest(let code) = error {
                orderViewModel.errorMessage = "Pay now unavailable (\(code))."
            } else {
                orderViewModel.errorMessage = "Pay now failed. Try pay at pickup."
            }
        }
    }

    @MainActor
    private func confirmPrepaid(sessionId: String) async {
        isSubmitting = true
        paymentPhase = .confirming
        defer { isSubmitting = false }
        do {
            let order = try await orderViewModel.confirmCheckout(sessionId: sessionId)
            paymentPhase = .done
            await finishCheckoutSuccess(order)
        } catch {
            paymentPhase = .failed
            if case Errors.failedRequest(let code) = error {
                if code == 410 {
                    orderViewModel.errorMessage = "Checkout expired. Close and try Pay now again."
                } else {
                    orderViewModel.errorMessage =
                        "Payment confirm failed (\(code)). Contact the café if charged."
                }
            } else {
                orderViewModel.errorMessage = "Payment confirm failed. Contact the café if charged."
            }
        }
    }

    @MainActor
    private func finishCheckoutSuccess(_ order: Order) async {
        cartViewModel.clear()
        useLoyaltyPoints = false
        stripeSheetFields = nil
        pendingCheckoutSessionId = nil
        paymentPhase = .idle
        orderViewModel.errorMessage = nil
        placedOrderId = order.id
        showsReview = false
        if let id = authenticationViewModel.user?.id {
            await loyalty.fetchLoyalty(userId: id)
        }
        let paid = order.totalCents ?? loyaltyQuote.payableCents
        var message = "Order #\(order.id.prefix(6)) · \(CurrencyHelper.format(cents: paid))"
        if order.paymentStatus == .paid {
            message += " · paid"
        } else if order.paymentStatus == .waived {
            message += " · covered by points"
        } else {
            message += " · pay at pickup"
        }
        if let spent = order.loyaltyPointsSpent, spent > 0 {
            message += " (−\(spent) pts)"
        }
        appNotificationCenter.show(message, iconSystemName: successIcon, duration: 3)
    }

    @MainActor
    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill, let item = prefillItem, item.isAvailable else { return }
        didApplyPrefill = true
        handleAdd(item)
    }
}

// MARK: - Lifecycle

struct OrderFlowLifecycle: ViewModifier {
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter

    @Binding var itemToCustomize: MenuItem?
    @Binding var showsReview: Bool
    @Binding var pickupASAP: Bool
    @Binding var pickupTime: Date
    @Binding var isSubmitting: Bool
    @Binding var placedOrderId: String?
    @Binding var searchTask: Task<Void, Never>?
    @Binding var useLoyaltyPoints: Bool
    @Binding var paymentPhase: CheckoutPaymentPhase
    @Binding var stripeSheetFields: StripeSheetConfigFields?
    @Binding var pendingCheckoutSessionId: String?
    var loyaltyQuote: LoyaltyCheckoutQuote
    var pointsBalance: Int
    var programEnabled: Bool
    var showPayNow: Bool
    var showPayAtPickup: Bool
    var onAppearPrefill: @MainActor () -> Void
    var reloadMenu: @MainActor () async -> Void
    var loadLoyaltyContext: @MainActor () async -> Void
    var checkout: @MainActor () async -> Void
    var preparePayNow: @MainActor () async -> Void
    var confirmPrepaid: @MainActor (String) async -> Void

#if os(Android)
    private let successIcon = "orders"
    private let warningIcon = "orders"
#else
    private let successIcon = "checkmark.circle.fill"
    private let warningIcon = "exclamationmark.triangle.fill"
#endif

    func body(content: Content) -> some View {
        content
            .task {
                menuViewModel.filterAvailable = true
                menuViewModel.includeDeleted = false
                menuViewModel.filterTagId = nil
                if menuViewModel.catalogNeedsRefresh || menuViewModel.items.isEmpty {
                    await reloadMenu()
                } else {
                    await menuViewModel.checkCatalogVersion()
                    if menuViewModel.catalogNeedsRefresh {
                        await reloadMenu()
                    }
                }
                await loadLoyaltyContext()
                onAppearPrefill()
            }
            .refreshable {
                await reloadMenu()
            }
            .onChange(of: menuViewModel.catalogNeedsRefresh) { _, needsRefresh in
                guard needsRefresh else { return }
                // Guest order surface: auto-refresh when the catalog bumps.
                Task { await reloadMenu() }
            }
            .onChange(of: menuViewModel.searchQuery) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await reloadMenu()
                }
            }
            .onChange(of: menuViewModel.items) { _, _ in
                let removed = cartViewModel.removeUnavailableItems(using: menuViewModel.items)
                if removed > 0 {
                    orderViewModel.errorMessage = "Some items were removed because they are unavailable."
                    appNotificationCenter.show(
                        "\(removed) unavailable item\(removed == 1 ? "" : "s") removed from your cart.",
                        iconSystemName: warningIcon
                    )
                }
            }
            .sheet(item: $itemToCustomize) { item in
                AddToCartSheet(item: item) { qty, size in
                    cartViewModel.add(item: item, quantity: qty, size: size)
                    placedOrderId = nil
                    appNotificationCenter.show(
                        "\(item.name) added to your cart.",
                        iconSystemName: successIcon,
                        duration: 2.0
                    )
                }
            }
            .sheet(isPresented: $showsReview) {
                CheckoutReviewSheet(
                    lines: cartViewModel.lines,
                    quote: loyaltyQuote,
                    pointsBalance: pointsBalance,
                    programEnabled: programEnabled,
                    showPayNow: showPayNow,
                    showPayAtPickup: showPayAtPickup,
                    paymentPhase: paymentPhase,
                    stripeSheetFields: stripeSheetFields,
                    errorMessage: orderViewModel.errorMessage,
                    useLoyaltyPoints: $useLoyaltyPoints,
                    pickupASAP: $pickupASAP,
                    pickupTime: $pickupTime,
                    isSubmitting: isSubmitting,
                    onAdjust: { line, adjustment in
                        if adjustment < 0 {
                            cartViewModel.decrement(line)
                        } else {
                            cartViewModel.increment(line)
                        }
                    },
                    onRemove: { cartViewModel.remove($0) },
                    onPlaceOrder: {
                        Task { await checkout() }
                    },
                    onPreparePayNow: {
                        Task { await preparePayNow() }
                    },
                    onPaymentCompleted: { sessionId in
                        Task { await confirmPrepaid(sessionId) }
                    },
                    onPaymentCanceled: {
                        paymentPhase = .idle
                        stripeSheetFields = nil
                        pendingCheckoutSessionId = nil
                    }
                )
                .onAppear {
                    paymentPhase = .idle
                    stripeSheetFields = nil
                    pendingCheckoutSessionId = nil
                }
            }
    }
}

// MARK: - Cart chrome

struct CartSummaryBar: View {
    let itemCount: Int
    let totalCents: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Text("\(itemCount)")
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.appColor)
                    .frame(width: 28, height: 28)
                    .background(Color.appOnAccent)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(itemCount == 1 ? "1 item in your cart" : "\(itemCount) items in your cart")
                        .font(AppFont.footnote())
                    Text(
                        CurrencyHelper.dollars(fromCents: totalCents),
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .font(AppFont.headline())
                }
                Spacer()
                Text("Review order")
                    .font(AppFont.button())
            }
            .foregroundStyle(Color.appOnAccent)
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 52)
            .background(Color.appColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(itemCount) items in cart. Review order, total \(CurrencyHelper.format(cents: totalCents))."
        )
    }
}

struct CheckoutReviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let lines: [CartLine]
    let quote: LoyaltyCheckoutQuote
    let pointsBalance: Int
    let programEnabled: Bool
    let showPayNow: Bool
    let showPayAtPickup: Bool
    let paymentPhase: CheckoutPaymentPhase
    let stripeSheetFields: StripeSheetConfigFields?
    let errorMessage: String?
    @Binding var useLoyaltyPoints: Bool
    @Binding var pickupASAP: Bool
    @Binding var pickupTime: Date
    let isSubmitting: Bool
    let onAdjust: @MainActor (CartLine, Int) -> Void
    let onRemove: @MainActor (CartLine) -> Void
    let onPlaceOrder: @MainActor () -> Void
    let onPreparePayNow: @MainActor () -> Void
    let onPaymentCompleted: @MainActor (String) -> Void
    let onPaymentCanceled: @MainActor () -> Void

    private var reviewSubtitle: String {
        switch (showPayNow, showPayAtPickup) {
        case (true, true):
            return "Pay in the app or at the counter when you pick up"
        case (true, false):
            return "Pay in the app to place your order"
        case (false, true):
            return "Pickup at the counter · pay when you collect"
        case (false, false):
            return "Checkout is unavailable — ask staff to enable payments"
        }
    }

#if os(Android)
    private let minusIcon = "android_minus"
    private let plusIcon = "android_plus"
    private let trashIcon = "android_archive"
#else
    private let minusIcon = "minus"
    private let plusIcon = "plus"
    private let trashIcon = "trash"
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    SectionHeader(
                        title: "Review your order",
                        subtitle: reviewSubtitle
                    )

                    if let errorMessage, !errorMessage.isEmpty {
                        ErrorBanner(message: errorMessage)
                    }

                    SurfacePanel {
                        VStack(spacing: 0) {
                            ForEach(lines) { line in
                                HStack(alignment: .top, spacing: AppSpacing.sm) {
                                    MenuGlyph(
                                        category: line.item.category,
                                        imageURL: line.item.imageURL,
                                        size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(line.item.name)
                                            .font(AppFont.body())
                                        if let sizeName = line.sizeName, !sizeName.isEmpty {
                                            Text(sizeName)
                                                .font(AppFont.caption())
                                                .foregroundStyle(.secondary)
                                        }
                                        if line.item.redeemPointsCost > 0 {
                                            Text("Free for \(line.item.redeemPointsCost) pts")
                                                .font(AppFont.caption())
                                                .foregroundStyle(Color.appColor)
                                        }
                                        StepperChips(
                                            minusIcon: minusIcon,
                                            plusIcon: plusIcon,
                                            valueLabel: "\(line.quantity)",
                                            onMinus: { onAdjust(line, -1) },
                                            onPlus: { onAdjust(line, 1) }
                                        )
                                    }
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                                        Text(
                                            CurrencyHelper.dollars(fromCents: line.lineCents),
                                            format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                                        )
                                        .font(AppFont.callout())
                                        Button(role: .destructive) {
                                            onRemove(line)
                                        } label: {
                                            AppImage(name: trashIcon)
                                                .foregroundStyle(Color.appDanger)
                                        }
                                        .accessibilityLabel("Remove \(line.item.name)")
                                    }
                                }
                                .padding(.vertical, AppSpacing.sm)
                                if line.id != lines.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    if programEnabled {
                        PanelSection(
                            title: "Loyalty",
                            subtitle: "You have \(pointsBalance) pts · earn ~\(quote.pointsEarned) on this order"
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                Toggle("Yes — use my points for free eligible items", isOn: $useLoyaltyPoints)
                                    .font(AppFont.body())
                                    .disabled(quote.redeemableUnitCount == 0 || pointsBalance <= 0)
                                if useLoyaltyPoints && quote.discountCents > 0 {
                                    Text("Applies −\(quote.pointsSpent) pts · saves \(CurrencyHelper.format(cents: quote.discountCents))")
                                        .font(AppFont.footnote())
                                        .foregroundStyle(Color.appColor)
                                } else if quote.redeemableUnitCount == 0 {
                                    Text("No redeemable items in this cart.")
                                        .font(AppFont.footnote())
                                        .foregroundStyle(.secondary)
                                } else if pointsBalance <= 0 {
                                    Text("Earn points on paid items, then redeem next time.")
                                        .font(AppFont.footnote())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Leave off to pay full price and keep your points.")
                                        .font(AppFont.footnote())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    PanelSection(title: "Pickup", subtitle: "When should we have it ready?") {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Toggle("ASAP", isOn: $pickupASAP)
                                .font(AppFont.body())
                            if !pickupASAP {
                                DatePicker(
                                    "Pickup time",
                                    selection: $pickupTime,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .font(AppFont.body())
                            }
                            Text(pickupPaymentHint)
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                        }
                    }

                    SurfacePanel {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            if quote.discountCents > 0 {
                                HStack {
                                    Text("Subtotal")
                                        .font(AppFont.body())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(CurrencyHelper.format(cents: quote.subtotalCents))
                                        .font(AppFont.body())
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("Loyalty")
                                        .font(AppFont.body())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("−\(CurrencyHelper.format(cents: quote.discountCents))")
                                        .font(AppFont.body())
                                        .foregroundStyle(Color.appColor)
                                }
                            }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Total due")
                                        .font(AppFont.headline())
                                    Text(totalDueHint)
                                        .font(AppFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(
                                    CurrencyHelper.dollars(fromCents: quote.payableCents),
                                    format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                                )
                                .font(AppFont.title2())
                                .foregroundStyle(Color.appColor)
                            }
                        }
                    }

                    checkoutActions
                }
                .padding(AppSpacing.lg)
            }
            .background(Color.groupedBackgroundColor)
            .navigationTitle("Checkout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Continue browsing") { dismiss() }
                }
            }
        }
    }

    private var pickupPaymentHint: String {
        switch (showPayNow, showPayAtPickup) {
        case (true, true):
            return "Choose Pay now for card/wallets, or pay at the counter."
        case (true, false):
            return "Pay now required — card or wallet in the app."
        case (false, true):
            return "Pay at pickup — no card charge in the app."
        case (false, false):
            return "No payment method is available right now."
        }
    }

    private var totalDueHint: String {
        switch (showPayNow, showPayAtPickup) {
        case (true, true):
            return "Pay now: card total includes Stripe Tax when configured. Or pay at pickup."
        case (true, false):
            return "Card total includes Stripe Tax when configured."
        case (false, true):
            return "Taxes and payment are handled at pickup."
        case (false, false):
            return "Ask staff to turn on pay at pickup or in-app payments."
        }
    }

    @ViewBuilder
    private var checkoutActions: some View {
        VStack(spacing: AppSpacing.sm) {
            if showPayNow {
                payNowAction
            }
            if showPayAtPickup {
                PrimaryButton(
                    title: isSubmitting && !showPayNow
                        ? "Placing order…"
                        : (showPayNow ? "Pay at pickup" : "Place order"),
                    fillWidth: true
                ) {
                    onPlaceOrder()
                }
                .disabled(lines.isEmpty || isSubmitting)
                .opacity(lines.isEmpty ? 0.55 : 1)
            } else if !showPayNow {
                Text("Checkout unavailable. Ask staff to enable pay at pickup or in-app payments.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var payNowAction: some View {
        if paymentPhase == .readyForSheet, let fields = stripeSheetFields {
#if canImport(SkipStripe) && !os(macOS)
            let config = StripePaymentConfiguration(
                publishableKey: fields.publishableKey,
                merchantName: fields.merchantName,
                customerID: fields.customerID,
                ephemeralKeySecret: fields.ephemeralKeySecret,
                clientSecret: fields.clientSecret
            )
            StripePaymentButton(configuration: config, completion: { result in
                switch result {
                case .completed:
                    onPaymentCompleted(fields.sessionId)
                case .canceled:
                    onPaymentCanceled()
                case .failed:
                    onPaymentCanceled()
                }
            }) {
                Text(isSubmitting ? "Processing…" : "Complete payment · \(CurrencyHelper.format(cents: fields.amountCents))")
                    .font(AppFont.button())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
#else
            SecondaryButton(
                title: "Pay now unavailable on this platform",
                fillWidth: true
            ) {}
            .disabled(true)
#endif
        } else {
            PrimaryButton(
                title: paymentPhase == .preparing || paymentPhase == .confirming
                    ? "Preparing payment…"
                    : "Pay now",
                fillWidth: true
            ) {
                onPreparePayNow()
            }
            .disabled(lines.isEmpty || isSubmitting)
            .opacity(lines.isEmpty ? 0.55 : 1)
        }
    }
}

// MARK: - Customize sheet

struct AddToCartSheet: View {
    @Environment(\.dismiss) var dismiss
    let item: MenuItem
    var onAdd: (Int, MenuSizeOption?) -> Void
    @State var quantity: Int = 1
    @State var selectedIndex: Int = 0

#if os(Android)
    let minusIcon = "android_minus"
    let plusIcon = "android_plus"
#else
    let minusIcon = "minus"
    let plusIcon = "plus"
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        MenuGlyph(category: item.category, imageURL: item.imageURL, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(AppFont.title2())
                            if let desc = item.description, !desc.isEmpty {
                                Text(desc)
                                    .font(AppFont.subheadline())
                                    .foregroundStyle(.secondary)
                            }
                            if let allergens = item.allergens, !allergens.isEmpty {
                                Text("Contains \(allergens.map(\.rawValue).joined(separator: ", "))")
                                    .font(AppFont.caption())
                                    .foregroundStyle(Color.appWarning)
                            }
                            Text(
                                CurrencyHelper.dollars(fromCents: item.priceCents),
                                format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                            )
                            .font(AppFont.headline())
                            .foregroundStyle(Color.appColor)
                        }
                    }

                    SurfacePanel {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            if let opts = item.sizeOptions, !opts.isEmpty {
                                Text("Size")
                                    .font(AppFont.footnote())
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(opts.indices, id: \.self) { idx in
                                            let opt = opts[idx]
                                            Button {
                                                selectedIndex = idx
                                            } label: {
                                                StatusChip(
                                                    text: "\(opt.name) +\(CurrencyHelper.format(cents: opt.priceDeltaCents))",
                                                    tone: .neutral,
                                                    selected: selectedIndex == idx
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            Text("Quantity")
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                            StepperChips(
                                minusIcon: minusIcon,
                                plusIcon: plusIcon,
                                valueLabel: "\(quantity)",
                                onMinus: { if quantity > 1 { quantity -= 1 } },
                                onPlus: { if quantity < 20 { quantity += 1 } }
                            )
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Color.groupedBackgroundColor)
            .navigationTitle("Customize")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let size = (item.sizeOptions ?? []).isEmpty ? nil : item.sizeOptions![selectedIndex]
                        onAdd(quantity, size)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
