//
//  MenuPricingView.swift
//  CafeSmartDev
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

    var body: some View {
        ScreenCanvas {
            SectionHeader(
                title: "Menu & pricing",
                subtitle: "Edit names, prices, and availability")

            if let err = menuViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            if menuViewModel.isLoading {
                LoadingBlock()
            } else if items.isEmpty {
                EmptyState(
                    title: "No menu items yet",
                    subtitle: "Pricing edits appear after menu sync."
                )
            } else {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(items.indices, id: \.self) { idx in
                        SurfacePanel {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                TextField("Item name", text: $items[idx].name)
                                    .font(AppFont.body())

                                AdaptiveDetailRow {
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
                                    .font(AppFont.body())
                                    .frame(maxWidth: 160, alignment: .leading)
                                } actions: {
                                    Toggle("Available", isOn: $items[idx].isAvailable)
                                        .font(AppFont.footnote())
                                }

                                HStack(spacing: 8) {
                                    if let category = items[idx].category, !category.isEmpty {
                                        StatusChip(text: category, tone: .neutral)
                                    }
                                    if let prep = items[idx].prepSeconds, prep > 0 {
                                        StatusChip(text: "Prep \(max(1, prep/60))m", tone: .accent)
                                    }
                                    if let allergens = items[idx].allergens, !allergens.isEmpty {
                                        StatusChip(text: "Allergens \(allergens.count)", tone: .warning)
                                    }
                                }
                            }
                        }
                    }

                    PrimaryButton(title: "Save changes", fillWidth: true) {
                        saveChangesAsync()
                    }
                }
            }
        }
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
