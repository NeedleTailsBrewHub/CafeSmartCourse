//
//  OrderFlowView.swift
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
import BSON
import ConnectionManagerKit

enum CurrencyHelper {
    static func dollars(fromCents cents: Int) -> Double {
        Double(cents) / 100.0
    }
}

struct OrderFlowView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @State var items: [MenuItem] = []
    @State var cart: [CartLine] = []
    @State var itemToCustomize: MenuItem? = nil
    
#if os(Android)
    let minusIcon = "android_minus"
#else
    let minusIcon = "minus"
#endif
    
    var totalCents: Int {
        cart.map { $0.lineCents }.reduce(0, +)
    }
    var total: Double {
        CurrencyHelper.dollars(fromCents: totalCents)
    }
    
    @State var availableWidth: CGFloat = 0
    
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
                SectionHeader(title: "Order now", subtitle: "Quick add to cart")
                LazyVStack(spacing: AppSpacing.md) {
                    if menuViewModel.items.isEmpty && !orderViewModel.isLoading {
                        Text("No menu items.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    ForEach(items) { item in
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
                                    VStack(alignment: .leading) {
                                        Text("\(item.name)")
                                            .font(AppFont.headline())
                                        if let sub = item.subcategory, !sub.isEmpty {
                                            Text(sub).font(AppFont.footnote()).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(CurrencyHelper.dollars(fromCents: item.priceCents), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                        .font(AppFont.body())
                                    PrimaryButton(
                                        title: item.sizeOptions?.isEmpty == false ? "Customize" : "Add",
                                        fillWidth: true) {
                                        if let opts = item.sizeOptions, !opts.isEmpty {
                                            itemToCustomize = item
                                        } else {
                                            addToCart(item: item, quantity: 1, sizeDeltaCents: 0)
                                        }
                                    }
                                    .frame(maxWidth: 160)
                                }
                                if let opts = item.sizeOptions, !opts.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(opts.indices, id: \.self) { idx in
                                                let opt = opts[idx]
                                                Text("\(opt.name) +\(CurrencyHelper.dollars(fromCents: opt.priceDeltaCents), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))")
                                                    .font(AppFont.footnote())
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color.gray.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                    }
                }
                
                CardContainer(
                    padding: AppSpacing.lg,
                    cornerRadius: 16,
                    backgroundColor: .surfaceColor,
                    borderColor: .gray.opacity(0.15),
                    borderWidth: 1,
                    shadowEnabled: true,
                    shadowColor: .black.opacity(0.05),
                    shadowRadius: 10,
                    shadowX: 0,
                    shadowY: 6) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if cart.isEmpty {
                            Text("Cart is empty")
                                .font(AppFont.subheadline())
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(cart.indices, id: \.self) { idx in
                                let line = cart[idx]
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.item.name)
                                            .font(AppFont.body())
                                        HStack(spacing: 10) {
                                            if let sizeName = line.sizeName, !sizeName.isEmpty {
                                                if let sizeName = line.sizeName {
                                                    Text(sizeName)
                                                        .font(AppFont.footnote())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            HStack(spacing: 8) {
                                                Image(systemName: minusIcon)
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.gray.opacity(0.15))
                                                    .cornerRadius(14)
                                                    .onTapGesture {
                                                        if cart[idx].quantity > 1 {
                                                            cart[idx].quantity -= 1
                                                        }
                                                    }
                                                Text("\(cart[idx].quantity)")
                                                    .font(AppFont.body())
                                                    .frame(minWidth: 32, alignment: .center)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.gray.opacity(0.12))
                                                    .cornerRadius(8)
                                                Image(systemName: "plus")
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.gray.opacity(0.15))
                                                    .cornerRadius(14)
                                                    .onTapGesture {
                                                        if cart[idx].quantity < 20 {
                                                            cart[idx].quantity += 1
                                                        }
                                                    }
                                            }
                                            Spacer()
                                        }
                                    }
                                    Spacer()
                                    Text(CurrencyHelper.dollars(fromCents: line.lineCents), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                        .font(AppFont.body())
                                    Button(role: .destructive) {
                                        cart.remove(at: idx) } label: {
                                            Image(systemName: "trash")
                                        }
                                }
                            }
                        }
                        Divider()
                        HStack {
                            Text("Total")
                                .font(AppFont.headline())
                            Spacer()
                            Text(total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                .font(AppFont.title2())
                        }
                    }
                }
                PrimaryButton(title: "Checkout", fillWidth: true) {
                    Task {
                        await checkout()
                    }
                }
            }
            .padding()
        }
        .captureWidth(in: $availableWidth)
        .onAppear {
            items = menuViewModel.items.filter { $0.isAvailable }
        }
        .task {
            if menuViewModel.items.isEmpty {
                do {
                    try await menuViewModel.fetchMenu()
                    items = menuViewModel.items.filter { $0.isAvailable }
                } catch {
                    orderViewModel.errorMessage = "Failed to load menu."
                }
            }
        }
        .refreshable {
            do {
                try await menuViewModel.fetchMenu()
                items = menuViewModel.items.filter { $0.isAvailable }
            } catch {
                orderViewModel.errorMessage = "Failed to refresh menu."
            }
        }
        .onChange(of: menuViewModel.items) { _, _ in
            items = menuViewModel.items.filter { $0.isAvailable }
            // Prune cart lines for items that became unavailable
            let before = cart.count
            cart.removeAll { !$0.item.isAvailable }
            if cart.count < before {
                orderViewModel.errorMessage = "Some items were removed because they are unavailable."
            }
        }
        .navigationTitle("Order now")
        .sheet(item: $itemToCustomize) { item in
            AddToCartSheet(item: item) { qty, size in
                addToCart(item: item, quantity: qty, sizeDeltaCents: size?.priceDeltaCents ?? 0)
            }
        }
    }
}

extension OrderFlowView {
    
    @MainActor
    private func checkout() async {
        guard !cart.isEmpty else { return }
        
        let orderItems: [OrderItem] = cart.map { line in
            let minimalNotes = "Item: \(line.item.name) - qty=\(line.quantity)"
            return OrderItem(
                menuItemId: line.item.id,
                name: line.item.name,
                quantity: line.quantity,
                notes: minimalNotes)
        }
        let request = CreateOrderRequest(
            customerName: authenticationViewModel.user?.name ?? authenticationViewModel.user?.email ?? "",
            items: orderItems,
            pickupTime: nil,
            channel: .pickup,
            serviceType: .barista,
            tableId: nil,
            guests: nil,
            reservationId: nil)
        Task.detached {
            let encoded = try BSONEncoder().encode(request).makeData()
            try await WebSocketClient.shared.sendBinary(encoded, to: "/api/auth/ws/merchant")
        }
        do { _ = try await orderViewModel.createOrder(request)
            cart.removeAll()
        } catch {
            logger.error("Checkout failed: \(String(describing: error))")
        }
    }
    
    @MainActor
    private func addToCart(item: MenuItem, quantity: Int, sizeDeltaCents: Int) {
        if let idx = cart.firstIndex(where: { $0.item.id == item.id && $0.sizeDeltaCents == sizeDeltaCents }) {
            cart[idx].quantity += quantity
        } else {
            let sizeName: String? = item.sizeOptions?.first(where: { $0.priceDeltaCents == sizeDeltaCents })?.name
            cart.append(CartLine(item: item, quantity: quantity, sizeDeltaCents: sizeDeltaCents, sizeName: sizeName))
        }
    }
}


// MARK: - Models & Sheets

struct AddToCartSheet: View {
    @Environment(\.dismiss) var dismiss
    let item: MenuItem
    var onAdd: (Int, MenuSizeOption?) -> Void
    @State var quantity: Int = 1
    @State var selectedIndex: Int = 0
    
#if os(Android)
    let minusIcon = "android_minus"
#else
    let minusIcon = "minus"
#endif
    
    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    if let opts = item.sizeOptions, !opts.isEmpty {
                        Picker("Size", selection: $selectedIndex) {
                            ForEach(opts.indices, id: \.self) { idx in
                                let opt = opts[idx]
                                Text("\(opt.name) (+\(CurrencyHelper.dollars(fromCents: opt.priceDeltaCents), format: .currency(code: Locale.current.currency?.identifier ?? "USD")))")
                                    .tag(idx)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: minusIcon)
                            .frame(width: 28, height: 28)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(14)
                            .onTapGesture {
                                if quantity > 1 {
                                    quantity -= 1
                                }
                            }
                        Text("Quantity: \(quantity)")
                            .frame(minWidth: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(14)
                            .onTapGesture {
                                if quantity < 20 {
                                    quantity += 1
                                }
                            }
                    }
                }
            }
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


