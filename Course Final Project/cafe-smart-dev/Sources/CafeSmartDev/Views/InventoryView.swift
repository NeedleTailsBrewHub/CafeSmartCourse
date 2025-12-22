//
//  InventoryView.swift
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
    
    @State var availableWidth: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if let err = inventoryViewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(AppFont.footnote())
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                SectionHeader(title: "Inventory", subtitle: "Track current stock")
                LazyVStack(spacing: AppSpacing.md) {
                    if inventoryViewModel.isLoading {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    if inventoryViewModel.items.isEmpty && !inventoryViewModel.isLoading {
                        Text("No inventory items yet.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    ForEach(inventoryViewModel.items) { item in
                        CardContainer(
                            padding: AppSpacing.md,
                            cornerRadius: 16,
                            backgroundColor: .surfaceColor,
                            borderColor: .separatorColor.opacity(0.35),
                            borderWidth: 1,
                            shadowEnabled: true,
                            shadowColor: .black.opacity(0.05),
                            shadowRadius: 10,
                            shadowX: 0,
                            shadowY: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(AppFont.headline())
                                        Text("\(item.quantity) \(item.unit) in stock")
                                            .font(AppFont.subheadline())
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 8) {
                                            if let supplier = item.supplier, !supplier.isEmpty {
                                                Label(supplier, systemImage: shippingBoxIcon)
                                                    .font(AppFont.footnote())
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let storage = item.storage {
                                                Label(storage.rawValue.capitalized, systemImage: storage == .frozen ? snowflakeIcon : (storage == .refrigerated ? thermometorIcon : archiveBoxIcon))
                                                    .font(AppFont.footnote())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if item.quantity <= item.reorderThreshold {
                                            Text("Low stock: reorder threshold \(item.reorderThreshold)")
                                                .font(AppFont.footnote())
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    HStack(spacing: AppSpacing.sm) {
                                        IconChip(name: minusIcon)
                                            .onTapGesture {
                                                adjustAsync(item: item, delta: -1)
                                            }
                                        IconChip(name: plusIcon)
                                            .onTapGesture {
                                                adjustAsync(item: item, delta: 1)
                                            }
                                        PrimaryButton(title: "Edit", fillWidth: true) {
                                            selectedForEdit = item
                                        }
                                        .frame(minWidth: 0, maxWidth: 160)
                                    }
                                }
                            }
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .captureWidth(in: $availableWidth)
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
//            InventoryEditSheet(item: item) { updated in
//                saveInventoryUpdateAsync(updated)
//            }
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

