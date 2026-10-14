//
//  InventoryEditSheet.swift
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

struct InventoryEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var item: InventoryItem
    var onSave: (InventoryItem) -> Void
    
    #if os(Android)
    private let minusIcon = "android_minus"
    private let plusIcon = "android_plus"
    #else
    private let minusIcon = "minus"
    private let plusIcon = "plus"
    #endif
    
    var body: some View {
        NavigationStack {
            ScreenCanvas {
                PanelSection(title: "General", subtitle: "Identity and supplier") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        AppTextField(placeholder: "Name", text: $item.name)
                        Text("SKU \(item.sku)")
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                        AppTextField(placeholder: "Unit", text: $item.unit)
                        AppTextField(
                            placeholder: "Supplier",
                            text: Binding(
                                get: { item.supplier ?? "" },
                                set: { item.supplier = $0.isEmpty ? nil : $0 }
                            )
                        )
                    }
                }

                PanelSection(title: "Stock", subtitle: "On-hand and reorder") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        #if !os(Android)
                        Stepper(value: $item.quantity, in: 0...1_000_000) {
                            Text("Quantity: \(item.quantity)")
                        }
                        Stepper(value: $item.reorderThreshold, in: 0...1_000_000) {
                            Text("Reorder threshold: \(item.reorderThreshold)")
                        }
                        #else
                        quantityRow(title: "Quantity", value: $item.quantity)
                        quantityRow(title: "Reorder threshold", value: $item.reorderThreshold)
                        #endif
                    }
                }

                PanelSection(title: "Advanced", subtitle: "Storage, cost, and planning") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Picker("Storage", selection: Binding(
                            get: { item.storage ?? .ambient },
                            set: { item.storage = $0 }
                        )) {
                            Text("Ambient").tag(StorageType.ambient)
                            Text("Refrigerated").tag(StorageType.refrigerated)
                            Text("Frozen").tag(StorageType.frozen)
                        }
                        optionalIntField("Shelf life (days)", value: $item.shelfLifeDays)
                        optionalIntField("Lead time (days)", value: $item.leadTimeDays)
                        optionalIntField("Par level", value: $item.parLevel)
                        optionalIntField("Reorder qty", value: $item.reorderQuantity)
                        optionalIntField("Cost per unit (cents)", value: $item.costPerUnitCents)
                        AppTextField(
                            placeholder: "Barcode",
                            text: Binding(
                                get: { item.barcode ?? "" },
                                set: { item.barcode = $0.isEmpty ? nil : $0 }
                            )
                        )
                        AppTextField(
                            placeholder: "Supplier SKU",
                            text: Binding(
                                get: { item.supplierSku ?? "" },
                                set: { item.supplierSku = $0.isEmpty ? nil : $0 }
                            )
                        )
                        optionalIntField("Safety stock", value: $item.safetyStock)
                        optionalIntField("Reserved qty", value: $item.reservedQuantity)
                    }
                }
            }
            #if !os(Android)
            .navigationTitle("Edit item")
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(item)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quantityRow(title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            StepperChips(
                minusIcon: minusIcon,
                plusIcon: plusIcon,
                valueLabel: "\(value.wrappedValue)",
                onMinus: {
                    if value.wrappedValue > 0 {
                        value.wrappedValue -= 1
                    }
                },
                onPlus: {
                    if value.wrappedValue < 1_000_000 {
                        value.wrappedValue += 1
                    }
                }
            )
        }
    }

    private func optionalIntField(_ title: String, value: Binding<Int?>) -> some View {
        AppTextField(
            placeholder: title,
            text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = Int($0) }
            )
        )
    }
}
