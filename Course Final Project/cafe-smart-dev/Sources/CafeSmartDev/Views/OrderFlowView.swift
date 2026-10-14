//
//  OrderFlowView.swift
//  CafeSmartDev
//

import SwiftUI
import BinaryCodable
import ConnectionManagerKit

struct OrderFlowView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var items: [MenuItem] = []
    @State var itemToCustomize: MenuItem? = nil
    @State var isSubmitting = false
    @State var selectedCategory: String? = nil
    @State var searchQuery = ""
    @State var showsReview = false

    private var categories: [String] {
        Array(Set(items.compactMap(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var searchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Full loaded menu (Final API returns the complete list — not paginated chunks).
    /// Search always scans the entire list; category chips only apply when search is empty.
    private var filteredItems: [MenuItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return items.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
                    || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
                    || ($0.subcategory?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        if let selectedCategory, !selectedCategory.isEmpty {
            return items.filter { $0.category == selectedCategory }
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

    private var groupedItems: [(String, [MenuItem])] {
        var order: [String] = []
        var map: [String: [MenuItem]] = [:]
        for item in filteredItems {
            let key = (item.category?.isEmpty == false) ? item.category! : "More"
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
        menuCanvas
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
            .modifier(OrderFlowLifecycle(
                items: $items,
                itemToCustomize: $itemToCustomize,
                showsReview: $showsReview,
                isSubmitting: $isSubmitting,
                load: loadMenu,
                checkout: checkout
            ))
    }

#if os(macOS)
    private var macBody: some View {
        HSplitView {
            menuCanvas
                .frame(minWidth: 420)
            cartSidebar
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        }
        .background(Color.groupedBackgroundColor)
        .modifier(OrderFlowLifecycle(
            items: $items,
            itemToCustomize: $itemToCustomize,
            showsReview: $showsReview,
            isSubmitting: $isSubmitting,
            load: loadMenu,
            checkout: checkout
        ))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await loadMenu(showError: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh menu")
            }
        }
    }

    private var cartSidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(
                title: "Cart",
                subtitle: cartViewModel.isEmpty
                    ? "Add items from the menu"
                    : "\(cartViewModel.itemCount) item\(cartViewModel.itemCount == 1 ? "" : "s")"
            )
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
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.surfaceColor)
    }

    private func cartLineRow(_ line: CartLine) -> some View {
        SurfacePanel {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                MenuGlyph(category: line.item.category, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.item.name)
                        .font(AppFont.body())
                    if let sizeName = line.sizeName, !sizeName.isEmpty {
                        Text(sizeName)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    StepperChips(
                        minusIcon: "minus",
                        plusIcon: "plus",
                        valueLabel: "\(line.quantity)",
                        onMinus: { cartViewModel.decrement(line) },
                        onPlus: { cartViewModel.increment(line) }
                    )
                }
                Spacer()
                Text(
                    CurrencyHelper.dollars(fromCents: line.lineCents),
                    format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                )
                .font(AppFont.callout())
            }
        }
    }
#endif

    private var menuCanvas: some View {
#if os(macOS)
        macMenuCanvas
#else
        phoneMenuCanvas
#endif
    }

#if os(macOS)
    private var macMenuCanvas: some View {
        ScreenCanvas {
            menuHeader
            menuContent
        }
        .navigationTitle("Order")
    }
#endif

    private var phoneMenuCanvas: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Menu")
                    .font(AppFont.title2())
                Text(searchActive
                     ? "Searching all \(items.count) items"
                     : "Pickup when ready · pay at the counter")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                AppTextField(
                    placeholder: "Search the full menu",
                    text: $searchQuery,
                    leadingSystemImage: searchIcon
                )

                if !categories.isEmpty && !searchActive {
                    CategoryChipBar(categories: categories, selection: $selectedCategory)
                } else if searchActive {
                    Text("\(filteredItems.count) match\(filteredItems.count == 1 ? "" : "es")")
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.appColor)
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

                    if orderViewModel.isLoading && items.isEmpty {
                        LoadingBlock()
                    } else if items.isEmpty {
                        EmptyState(
                            title: "Menu is empty",
                            subtitle: "Pull to refresh once items are available."
                        )
                    } else if filteredItems.isEmpty {
                        EmptyState(
                            title: "No matches",
                            subtitle: searchActive
                                ? "Nothing matched that search across the full menu."
                                : "Try another category."
                        )
                    } else {
                        if !searchActive && selectedCategory == nil && !featuredItems.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Text("Featured")
                                    .font(AppFont.headline())
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppSpacing.sm) {
                                        ForEach(featuredItems) { item in
                                            FeaturedMenuCard(item: item) {
                                                handleAdd(item)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(groupedItems, id: \.0) { category, rows in
                            VStack(alignment: .leading, spacing: 0) {
                                if selectedCategory == nil || searchActive {
                                    Text(category)
                                        .font(AppFont.headline())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.bottom, AppSpacing.sm)
                                }
                                SurfacePanel(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                            MenuOrderRow(item: item, showsAdd: true) {
                                                handleAdd(item)
                                            }
                                            if index < rows.count - 1 {
                                                Divider().padding(.leading, 88)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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
        SectionHeader(
            title: "Today’s board",
            subtitle: searchActive
                ? "Searching all \(items.count) items"
                : "Search, customize, and send for pickup"
        )
        AppTextField(
            placeholder: "Search the full menu",
            text: $searchQuery,
            leadingSystemImage: searchIcon
        )
        if !categories.isEmpty && !searchActive {
            CategoryChipBar(categories: categories, selection: $selectedCategory)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let err = orderViewModel.errorMessage, !err.isEmpty {
            ErrorBanner(message: err)
        }
        if orderViewModel.isLoading && items.isEmpty {
            LoadingBlock()
        } else if items.isEmpty {
            EmptyState(title: "No menu items", subtitle: "Pull to refresh once the menu is available.")
        } else if filteredItems.isEmpty {
            EmptyState(title: "No matches", subtitle: "Try another search or category.")
        } else {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                ForEach(groupedItems, id: \.0) { category, rows in
                    VStack(alignment: .leading, spacing: 0) {
                        if selectedCategory == nil || searchActive {
                            Text(category)
                                .font(AppFont.headline())
                                .foregroundStyle(.secondary)
                                .padding(.bottom, AppSpacing.sm)
                        }
                        SurfacePanel(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                    MenuOrderRow(item: item, showsAdd: true) {
                                        handleAdd(item)
                                    }
                                    if index < rows.count - 1 {
                                        Divider().padding(.leading, 88)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func handleAdd(_ item: MenuItem) {
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

    @MainActor
    private func loadMenu(showError: Bool) async {
        do {
            try await menuViewModel.fetchMenu()
            items = menuViewModel.items.filter(\.isAvailable)
        } catch {
            if showError {
                orderViewModel.errorMessage = "Failed to load menu."
            }
        }
    }

    @MainActor
    private func checkout() async {
        guard !cartViewModel.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let orderItems: [OrderItem] = cartViewModel.lines.map { line in
            OrderItem(
                menuItemId: line.item.id,
                name: line.item.name,
                quantity: line.quantity,
                notes: line.sizeName.map { "Size: \($0)" }
            )
        }
        let request = CreateOrderRequest(
            customerName: authenticationViewModel.user?.name ?? authenticationViewModel.user?.email ?? "",
            items: orderItems,
            pickupTime: nil,
            channel: .pickup,
            serviceType: .barista,
            tableId: nil,
            guests: nil,
            reservationId: nil
        )
        do {
            let order = try await orderViewModel.createOrder(request)
            cartViewModel.clear()
            orderViewModel.errorMessage = nil
            showsReview = false
            appNotificationCenter.show(
                "Order #\(order.id.prefix(6).uppercased()) placed. We’ll have it ready soon.",
                iconSystemName: successIcon,
                duration: 4.0
            )
            Task {
                do {
                    let encoded = try BinaryEncoder().encode(request)
                    try await WebSocketClient.shared.sendBinary(encoded, to: Constants.wsMerchantRoute)
                } catch {
                    logger.info("Checkout WS notify failed: \(error)")
                }
            }
        } catch {
            if case Errors.failedRequest(let code) = error {
                orderViewModel.errorMessage = "Checkout failed (\(code)). Please try again."
            } else {
                orderViewModel.errorMessage = "Checkout failed. Please try again."
            }
            logger.error("Checkout failed: \(String(describing: error))")
        }
    }

    private var searchIcon: String {
#if os(Android)
        "android_note"
#else
        "magnifyingglass"
#endif
    }

    private var successIcon: String {
#if os(Android)
        "orders"
#else
        "checkmark.circle.fill"
#endif
    }
}

struct OrderFlowLifecycle: ViewModifier {
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @Binding var items: [MenuItem]
    @Binding var itemToCustomize: MenuItem?
    @Binding var showsReview: Bool
    @Binding var isSubmitting: Bool
    let load: (Bool) async -> Void
    let checkout: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { items = menuViewModel.items.filter(\.isAvailable) }
            .task {
                if menuViewModel.items.isEmpty {
                    await load(true)
                }
            }
            .refreshable { await load(true) }
            .onChange(of: menuViewModel.items) { _, _ in
                items = menuViewModel.items.filter(\.isAvailable)
                let removed = cartViewModel.removeUnavailableItems(using: menuViewModel.items)
                if removed > 0 {
                    appNotificationCenter.show(
                        "\(removed) unavailable item\(removed == 1 ? "" : "s") removed from your cart.",
                        iconSystemName: warningIcon
                    )
                }
            }
            .sheet(item: $itemToCustomize) { item in
                AddToCartSheet(item: item) { qty, size in
                    cartViewModel.add(item: item, quantity: qty, size: size)
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
                    totalCents: cartViewModel.totalCents,
                    isSubmitting: isSubmitting,
                    onAdjust: { line, adjustment in
                        if adjustment < 0 {
                            cartViewModel.decrement(line)
                        } else {
                            cartViewModel.increment(line)
                        }
                    },
                    onRemove: { cartViewModel.remove($0) },
                    onPlaceOrder: { Task { await checkout() } }
                )
            }
    }

    private var successIcon: String {
#if os(Android)
        "orders"
#else
        "checkmark.circle.fill"
#endif
    }

    private var warningIcon: String {
#if os(Android)
        "orders"
#else
        "exclamationmark.triangle.fill"
#endif
    }
}

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
            .padding(.vertical, 12)
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
    let totalCents: Int
    let isSubmitting: Bool
    let onAdjust: (CartLine, Int) -> Void
    let onRemove: (CartLine) -> Void
    let onPlaceOrder: () -> Void

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
                        subtitle: "Pickup at the counter · pay when you collect"
                    )

                    SurfacePanel {
                        VStack(spacing: 0) {
                            ForEach(lines) { line in
                                HStack(alignment: .top, spacing: AppSpacing.sm) {
                                    MenuGlyph(category: line.item.category, size: 40)
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

                    SurfacePanel {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total")
                                    .font(AppFont.headline())
                                Text("Taxes and payment are handled at pickup.")
                                    .font(AppFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(
                                CurrencyHelper.dollars(fromCents: totalCents),
                                format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                            )
                            .font(AppFont.title2())
                            .foregroundStyle(Color.appColor)
                        }
                    }

                    PrimaryButton(
                        title: isSubmitting ? "Placing order…" : "Place order",
                        fillWidth: true,
                        action: onPlaceOrder
                    )
                    .disabled(lines.isEmpty || isSubmitting)
                    .opacity(lines.isEmpty ? 0.55 : 1)
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
}

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
                        MenuGlyph(category: item.category, size: 64)
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
