//
//  MyOrdersView.swift
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

struct MyOrdersView: View {
    @Environment(OrderViewModel.self) var orderViewModel
    @State var availableWidth: CGFloat = 0
    @State var orders: [Order] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if let err = orderViewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(AppFont.footnote())
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                SectionHeader(title: "My orders", subtitle: "Recent activity")
                LazyVStack(spacing: AppSpacing.md) {
                    if orderViewModel.orders.isEmpty {
                        Text("No orders yet.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    ForEach(orders.reversed()) { order in
                        CardContainer(
                            padding: AppSpacing.md,
                            cornerRadius: 16,
                            backgroundColor: .surfaceColor,
                            borderColor: .gray.opacity(0.15),
                            borderWidth: 1,
                            shadowEnabled: true,
                            shadowColor: .black.opacity(0.05),
                            shadowRadius: 10,
                            shadowX: 0,
                            shadowY: 6) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(order.id.prefix(6))")
                                        .font(AppFont.headline())
                                    Spacer()
                                    Text(order.status.rawValue.capitalized)
                                        .font(AppFont.footnote())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.appColor.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                HStack {
                                    if let name = order.customerName, !name.isEmpty {
                                        Text(name)
                                            .font(AppFont.footnote())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(order.items.count) items")
                                            .font(AppFont.footnote())
                                            .foregroundStyle(.secondary)
                                        if let when = order.pickupTime {
                                            Text(when, style: .time)
                                                .font(AppFont.footnote())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(order.items.indices, id: \.self) { idx in
                                        let item = order.items[idx]
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.name ?? "Item")
                                                .font(AppFont.body())
                                            Spacer()
                                            Text("x\(item.quantity)")
                                                .font(AppFont.footnote())
                                                .foregroundStyle(.secondary)
                                        }
                                        if let notes = item.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(AppFont.footnote())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if order.status == .pending {
                                    HStack {
                                        Spacer()
                                        Button(role: .destructive) {
                                            Task {
                                                await cancel(order: order)
                                            }
                                        } label: {
                                            Text("Cancel order")
                                        }
                                    }
                                }
                            }
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                        }
                    }
                    .onChange(of: orderViewModel.orders) { _, newValue in
                        print("New orders: \(newValue)")
                        self.orders = newValue
                    }
                }
                .padding()
            }
        }
        .captureWidth(in: $availableWidth)
        .navigationTitle("My orders")
        .task {
            print("Current orders: \(orderViewModel.orders)")
            if orderViewModel.orders.isEmpty {
                do {
                    try await orderViewModel.fetchOrders()
                    orders = orderViewModel.orders
                } catch {
                    orderViewModel.errorMessage = "Failed to load orders."
                }
            } else {
                orders = orderViewModel.orders
            }
        }
        .refreshable {
            do {
                try await orderViewModel.fetchOrders()
            } catch {
                orderViewModel.errorMessage = "Failed to refresh orders."
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


