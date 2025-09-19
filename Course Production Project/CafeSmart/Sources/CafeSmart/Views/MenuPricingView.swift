//
//  MenuPricingView.swift
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

struct MenuPricingView: View {
    @Environment(MenuViewModel.self) var menuViewModel

    @State var items: [MenuItem] = []
    @State var originalById: [String: MenuItem] = [:]
    @State var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if let err = menuViewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(AppFont.footnote())
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                SectionHeader(title: "Menu & pricing", subtitle: "Quick edits")
                LazyVStack(spacing: AppSpacing.md) {
                    if menuViewModel.isLoading {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    if items.isEmpty && !menuViewModel.isLoading {
                        Text("No menu items yet.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    ForEach(items.indices, id: \.self) { idx in
                        CardContainer(
                            padding: AppSpacing.md, cornerRadius: 16, backgroundColor: .surfaceColor,
                            borderColor: .gray.opacity(0.15), borderWidth: 1, shadowEnabled: true,
                            shadowColor: .black.opacity(0.05), shadowRadius: 10, shadowX: 0,
                            shadowY: 6
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center) {
                                    TextField("Item name", text: $items[idx].name)
                                        .font(AppFont.body())
                                    Spacer()
                                    TextField(
                                        "0.00",
                                        value: Binding<Double>(
                                            get: { Double(items[idx].priceCents) / 100.0 },
                                            set: {
                                                items[idx].priceCents = Int(($0 * 100.0).rounded())
                                            }
                                        ),
                                        format: .currency(
                                            code: Locale.current.currency?.identifier ?? "USD")
                                    )
                                    .multilineTextAlignment(.trailing)
//                                    .keyboardType(.decimalPad)
                                    .font(AppFont.body())
                                    .frame(width: 120)
                                    Toggle("", isOn: $items[idx].isAvailable).labelsHidden()
                                }
                                HStack(spacing: 8) {
                                    if let category = items[idx].category, !category.isEmpty {
                                        Text(category)
                                            .font(AppFont.footnote())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    if let prep = items[idx].prepSeconds, prep > 0 {
                                        Text("Prep \(max(1, prep/60))m")
                                            .font(AppFont.footnote())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    if let allergens = items[idx].allergens, !allergens.isEmpty {
                                        Text("Allergens \(allergens.count)")
                                            .font(AppFont.footnote())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                    }
                    PrimaryButton(title: "Save changes", fillWidth: true) {
                        saveChangesAsync()
                    }
                }
            }
            .padding()
        }
        .captureWidth(in: $availableWidth)
        .onAppear {
            items = menuViewModel.items
            originalById = Dictionary(uniqueKeysWithValues: menuViewModel.items.map { ($0.id, $0) })
        }
        .task {
            if menuViewModel.items.isEmpty {
                do {
                    try await menuViewModel.fetchMenu()
                    items = menuViewModel.items
                    originalById = Dictionary(
                        uniqueKeysWithValues: menuViewModel.items.map { ($0.id, $0) })
                } catch {
                    logger.log("Failed to load menu: \(error)")
                    menuViewModel.errorMessage = "Failed to load menu."
                }
            }
        }
        .refreshable {
            do {
                try await menuViewModel.fetchMenu()
                items = menuViewModel.items
                originalById = Dictionary(
                    uniqueKeysWithValues: menuViewModel.items.map { ($0.id, $0) })
            } catch {
                menuViewModel.errorMessage = "Failed to refresh menu."
            }
        }
        .navigationTitle("Menu & Pricing")
    }
}

extension MenuPricingView {
    @MainActor private func saveChanges() async {
        for item in items {
            guard let original = originalById[item.id] else { continue }
            var update = UpdateMenuItemRequest()
            var changed = false
            if item.name != original.name {
                update.name = item.name
                changed = true
            }
            if item.priceCents != original.priceCents {
                update.priceCents = item.priceCents
                changed = true
            }
            if item.isAvailable != original.isAvailable {
                update.isAvailable = item.isAvailable
                changed = true
            }
            if changed {
                do {
                    _ = try await menuViewModel.updateMenuItem(id: item.id, with: update)
                } catch {
                    logger.error("Failed to update menu item \(String(describing: error))")
                }
            }
        }
        originalById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private func saveChangesAsync() {
        Task { @MainActor in
            await saveChanges()
        }
    }
}
