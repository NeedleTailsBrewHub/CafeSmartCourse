//
//  InventoryView.swift
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

struct InventoryView: View {
    
    @Environment(InventoryViewModel.self) var inventoryViewModel
    @State var selectedForEdit: InventoryItem? = nil
    
#if os(Android)
    let minusIcon = "android_minus"
    let plusIcon = "android_plus"
    let shippingBoxIcon = "android_package"
    let thermometorIcon = "android_thermometer"
    let snowflakeIcon = "android_snowflake"
    let archiveBoxIcon = "android_archive"
#else
    let minusIcon = "minus"
    let plusIcon = "plus"
    let shippingBoxIcon = "shippingbox"
    let thermometorIcon = "thermometer"
    let snowflakeIcon = "snowflake"
    let archiveBoxIcon = "archivebox"
#endif
    
    var body: some View {
        ScreenCanvas {
            SectionHeader(
                title: "Stock",
                subtitle: "Adjust quantities or edit item details")

            if let err = inventoryViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            if inventoryViewModel.isLoading {
                LoadingBlock()
            } else if inventoryViewModel.items.isEmpty {
                EmptyState(
                    title: "No inventory yet",
                    subtitle: "Stock items will appear here after sync.",
                    systemImage: shippingBoxIcon
                )
            } else {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(inventoryViewModel.items) { item in
                        SurfacePanel {
                            AdaptiveDetailRow {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name)
                                        .font(AppFont.headline())
                                    Text("\(item.quantity) \(item.unit) in stock")
                                        .font(AppFont.subheadline())
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        if let supplier = item.supplier, !supplier.isEmpty {
                                            MetaLabel(icon: shippingBoxIcon, text: supplier)
                                        }
                                        if let storage = item.storage {
                                            let storageIcon = storage == .frozen
                                                ? snowflakeIcon
                                                : (storage == .refrigerated ? thermometorIcon : archiveBoxIcon)
                                            MetaLabel(icon: storageIcon, text: storage.rawValue.capitalized)
                                        }
                                    }
                                    if item.quantity <= item.reorderThreshold {
                                        StatusChip(
                                            text: "Low stock · reorder at \(item.reorderThreshold)",
                                            tone: .warning)
                                    }
                                    if let forecast = inventoryViewModel.restockBySku[item.sku], forecast.needRestock {
                                        StatusChip(
                                            text: "Forecast: reorder \(forecast.reorderQty) \(item.unit)",
                                            tone: .warning)
                                    }
                                }
                            } actions: {
                                HStack(spacing: AppSpacing.sm) {
                                    StepperChips(
                                        minusIcon: minusIcon,
                                        plusIcon: plusIcon,
                                        onMinus: { adjustAsync(item: item, delta: -1) },
                                        onPlus: { adjustAsync(item: item, delta: 1) }
                                    )
                                    .accessibilityElement(children: .contain)
                                    SecondaryButton(title: "Edit", fillWidth: false) {
                                        selectedForEdit = item
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory")
        .task {
            if inventoryViewModel.items.isEmpty {
                do {
                    try await inventoryViewModel.fetchInventory()
                } catch {
                    logger.error("Failed to Fetched inventory \(error)")
                    inventoryViewModel.errorMessage = "Failed to load inventory."
                }
            }
        }
        .refreshable {
            do {
                try await inventoryViewModel.fetchInventory()
            } catch {
                logger.error("Failed to Fetched inventory \(error)")
                inventoryViewModel.errorMessage = "Failed to refresh inventory."
            }
        }
        .sheet(item: $selectedForEdit) { item in
            InventoryEditSheet(item: item) { updated in
                saveInventoryUpdateAsync(updated)
            }
        }
    }
}


extension InventoryView {
    @MainActor private func adjust(item: InventoryItem, delta: Int) async {
        let newQuantity = max(0, item.quantity + delta)
        let request = UpdateInventoryItemRequest(quantity: newQuantity)
        do { _ = try await inventoryViewModel.updateInventoryItem(id: item.id, with: request) } catch {
            logger.error("Failed to adjust inventory: \(String(describing: error))")
        }
    }
    private func adjustAsync(item: InventoryItem, delta: Int) {
        Task { @MainActor in
            await adjust(item: item, delta: delta)
        }
    }
    private func saveInventoryUpdateAsync(_ updated: InventoryItem) {
        Task { @MainActor in
            let request = UpdateInventoryItemRequest(
                sku: updated.sku,
                name: updated.name,
                quantity: updated.quantity,
                reorderThreshold: updated.reorderThreshold,
                unit: updated.unit,
                supplier: updated.supplier,
                storage: updated.storage,
                shelfLifeDays: updated.shelfLifeDays,
                leadTimeDays: updated.leadTimeDays,
                parLevel: updated.parLevel,
                reorderQuantity: updated.reorderQuantity,
                costPerUnitCents: updated.costPerUnitCents,
                barcode: updated.barcode,
                supplierSku: updated.supplierSku,
                safetyStock: updated.safetyStock,
                reservedQuantity: updated.reservedQuantity
            )
            _ = try? await inventoryViewModel.updateInventoryItem(id: updated.id, with: request)
        }
    }
}
