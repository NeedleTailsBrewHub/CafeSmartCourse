//
//  MyOrdersView.swift
//  CafeSmartDev
//

import SwiftUI

struct MyOrdersView: View {
    @Environment(OrderViewModel.self) var orderViewModel
    var onStartOrder: (@MainActor () -> Void)? = nil
    @State var orderPendingCancel: Order?

#if os(Android)
    private let emptyIcon = "orders"
#else
    private let emptyIcon = "tray.full.fill"
#endif

    private var hasActiveOrders: Bool {
        orderViewModel.orders.contains {
            $0.status == .pending || $0.status == .preparing || $0.status == .ready
        }
    }

    var body: some View {
        ScreenCanvas {
            SectionHeader(
                title: "Your orders",
                subtitle: "Track pickup and manage pending tickets")

            if let err = orderViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            if orderViewModel.isLoading && orderViewModel.orders.isEmpty {
                LoadingBlock()
            } else if orderViewModel.orders.isEmpty {
                EmptyState(
                    title: "No orders yet",
                    subtitle: "When you place a pickup order, it will show up here.",
                    systemImage: emptyIcon,
                    actionTitle: onStartOrder == nil ? nil : "Order now",
                    action: onStartOrder
                )
            } else {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(orderViewModel.orders.reversed()) { order in
                        orderCard(order)
                    }
                }
            }
        }
        .navigationTitle("Orders")
        .task {
            await refreshOrders()
            while !Task.isCancelled && hasActiveOrders {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await refreshOrders(silent: true)
            }
        }
        .refreshable {
            await refreshOrders()
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
            Text("The kitchen will stop preparing this ticket.")
        }
    }

    @ViewBuilder
    private func orderCard(_ order: Order) -> some View {
        SurfacePanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AdaptiveDetailRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Order #\(order.id.prefix(6).uppercased())")
                            .font(AppFont.headline())
                        Text(order.createdAt, style: .time)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                } actions: {
                    StatusChip(
                        text: statusTitle(for: order.status),
                        tone: chipTone(for: order.status)
                    )
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
                        .padding(.vertical, AppSpacing.xs)
                        if idx < order.items.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(Color.elevatedSurfaceColor.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                if order.status == .pending {
                    DestructiveButton(title: "Cancel order", fillWidth: true) {
                        orderPendingCancel = order
                    }
                }
            }
        }
    }

    private func statusTitle(for status: OrderStatus) -> String {
        switch status {
        case .pending: return "Received"
        case .preparing: return "Being prepared"
        case .ready: return "Ready for pickup"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }

    private func friendlySize(from notes: String?) -> String? {
        guard let notes, notes.lowercased().hasPrefix("size:") else { return nil }
        let value = notes.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

#if os(Android)
    // Keep icon mapping local for MetaLabel if needed later.
#endif

    private func chipTone(for status: OrderStatus) -> StatusChipTone {
        switch status {
        case .pending: return .warning
        case .preparing, .ready: return .accent
        case .completed: return .success
        case .canceled: return .danger
        }
    }

    @MainActor
    private func refreshOrders(silent: Bool = false) async {
        do {
            try await orderViewModel.fetchOrders()
        } catch {
            if !silent {
                orderViewModel.errorMessage = "Failed to load orders."
            }
        }
    }
}

extension MyOrdersView {
    @MainActor private func cancel(order: Order) async {
        do {
            _ = try await orderViewModel.updateOrderStatus(id: order.id, status: .canceled)
            try? await orderViewModel.fetchOrders()
        } catch {
            orderViewModel.errorMessage = "Failed to cancel order."
        }
    }
}
