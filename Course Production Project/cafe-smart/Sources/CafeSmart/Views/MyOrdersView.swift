//
//  MyOrdersView.swift
//  CafeSmart
//
//  Order tracking — active / history cards matching marketplace home language.
//

import SwiftUI
import VenueSmartKit

struct MyOrdersView: View {
    @Environment(OrderViewModel.self) var orderViewModel
    var onStartOrder: (@MainActor () -> Void)? = nil
    @State var cancelingId: String?
    @State var orderPendingCancel: Order?
    @State var searchTask: Task<Void, Never>?
#if os(Android)
    private let emptyIcon = "orders"
    private let searchIcon = "android_tag"
#else
    private let emptyIcon = "tray.full.fill"
    private let searchIcon = "magnifyingglass"
#endif

    private var searchBinding: Binding<String> {
        Binding(
            get: { orderViewModel.searchQuery },
            set: { orderViewModel.searchQuery = $0 }
        )
    }

    private var activeOrders: [Order] {
        orderViewModel.orders
            .filter { $0.status == .pending || $0.status == .preparing || $0.status == .ready }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var pastOrders: [Order] {
        orderViewModel.orders
            .filter { $0.status == .completed || $0.status == .canceled }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScreenCanvas {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your orders")
                    .font(AppFont.title2())
                Text("Track pickup status · cancel while pending")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            AppTextField(
                placeholder: "Search orders…",
                text: searchBinding,
                leadingSystemImage: searchIcon)

            if let err = orderViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            if !activeOrders.isEmpty {
                LiveStatusBanner(
                    title: activeOrders.count == 1
                        ? "1 order in progress"
                        : "\(activeOrders.count) orders in progress",
                    subtitle: "We’ll notify you when it’s ready"
                )
            }

            if orderViewModel.isLoading && orderViewModel.orders.isEmpty {
                LoadingBlock()
            } else if orderViewModel.orders.isEmpty {
                EmptyState(
                    title: "No orders yet",
                    subtitle: "Place an order from the Menu tab to see it here.",
                    systemImage: emptyIcon,
                    actionTitle: onStartOrder == nil ? nil : "Order now",
                    action: onStartOrder
                )
            } else {
                if !activeOrders.isEmpty {
                    MarketplaceSection(title: "Active") {
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(activeOrders) { order in
                                orderCard(order, elevated: true)
                            }
                        }
                    }
                }
                if !pastOrders.isEmpty {
                    MarketplaceSection(title: "Order again") {
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(Array(pastOrders.prefix(40))) { order in
                                orderCard(order, elevated: false)
                            }
                        }
                    }
                }

                if orderViewModel.hasMore {
                    SecondaryButton(
                        title: orderViewModel.isLoadingMore ? "Loading…" : "Load more",
                        fillWidth: true
                    ) {
                        Task { await loadMore() }
                    }
                    .disabled(orderViewModel.isLoadingMore)
                }
            }
        }
        .navigationTitle("Orders")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .onChange(of: orderViewModel.searchQuery) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
        .confirmationDialog(
            "Cancel this order?",
            isPresented: Binding(
                get: { orderPendingCancel != nil },
                set: { if !$0 { orderPendingCancel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive) {
                if let order = orderPendingCancel {
                    Task { await cancel(order: order) }
                }
                orderPendingCancel = nil
            }
            Button("Keep order", role: .cancel) {
                orderPendingCancel = nil
            }
        } message: {
            Text("You can only cancel while the order is still pending.")
        }
    }

    @ViewBuilder
    private func orderCard(_ order: Order, elevated: Bool) -> some View {
        SurfacePanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AdaptiveDetailRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("#\(order.id.prefix(6).uppercased())")
                            .font(AppFont.headline())
                        Text(order.createdAt, style: .relative)
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                    }
                } actions: {
                    StatusChip(
                        text: statusTitle(for: order.status),
                        tone: chipTone(for: order.status))
                }

                HStack {
                    Text("\(order.items.count) item\(order.items.count == 1 ? "" : "s")")
                        .font(AppFont.footnote())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let when = order.pickupTime {
                        Text("Pickup \(when.formatted(date: .omitted, time: .shortened))")
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("ASAP pickup")
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.appColor)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(order.items.indices, id: \.self) { idx in
                        let item = order.items[idx]
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Item")
                                    .font(AppFont.body())
                                if let size = friendlySize(from: item.notes) {
                                    Text(size)
                                        .font(AppFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("×\(item.quantity)")
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        if idx < order.items.count - 1 {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
                .background(
                    elevated
                        ? Color.appColor.opacity(0.06)
                        : Color.elevatedSurfaceColor.opacity(0.65)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                if order.status == .pending {
                    DestructiveButton(
                        title: cancelingId == order.id ? "Canceling…" : "Cancel order",
                        fillWidth: true
                    ) {
                        orderPendingCancel = order
                    }
                    .disabled(cancelingId != nil)
                }
            }
        }
    }

    private func statusTitle(for status: OrderStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .preparing: return "Preparing"
        case .ready: return "Ready for pickup"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }

    private func chipTone(for status: OrderStatus) -> StatusChipTone {
        switch status {
        case .pending: return .warning
        case .preparing, .ready: return .accent
        case .completed: return .success
        case .canceled: return .danger
        }
    }

    private func friendlySize(from notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        if let range = notes.range(of: #"Size:\s*([^(·]+)"#, options: .regularExpression) {
            let matched = String(notes[range])
                .replacingOccurrences(of: "Size:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let cut = matched.split(separator: "(").first {
                let size = String(cut).trimmingCharacters(in: .whitespacesAndNewlines)
                return size.isEmpty ? nil : size
            }
        }
        return nil
    }

    @MainActor
    private func reload() async {
        do {
            try await orderViewModel.fetchOrders(reset: true, scope: .mine)
            orderViewModel.errorMessage = nil
        } catch {
            if RequestCancellation.isCancellation(error) { return }
            orderViewModel.errorMessage = "Failed to load orders."
        }
    }

    @MainActor
    private func loadMore() async {
        do {
            try await orderViewModel.loadMore()
        } catch {
            if RequestCancellation.isCancellation(error) { return }
            orderViewModel.errorMessage = "Failed to load more orders."
        }
    }
}

extension MyOrdersView {
    @MainActor private func cancel(order: Order) async {
        cancelingId = order.id
        defer { cancelingId = nil }
        do {
            _ = try await orderViewModel.updateOrderStatus(id: order.id, status: .canceled)
            try await orderViewModel.fetchOrders(reset: true, scope: .mine)
            orderViewModel.errorMessage = nil
        } catch {
            if case Errors.failedRequest(let code) = error {
                switch code {
                case 403:
                    orderViewModel.errorMessage = "This order can no longer be canceled."
                case 404:
                    orderViewModel.errorMessage = "Order not found. Pull to refresh."
                default:
                    orderViewModel.errorMessage = "Failed to cancel order (\(code))."
                }
            } else {
                orderViewModel.errorMessage = "Failed to cancel order."
            }
        }
    }
}
