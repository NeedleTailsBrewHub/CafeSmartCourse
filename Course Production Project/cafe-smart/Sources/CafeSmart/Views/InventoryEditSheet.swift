//
//  InventoryEditSheet.swift
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
            Form {
                Section("General") {
                    TextField("Name", text: $item.name)
                    Text("SKU \(item.sku)")
                    TextField("Unit", text: $item.unit)
                    TextField("Supplier", text: Binding(get: {
                        item.supplier ?? ""
                    }, set: {
                        item.supplier = $0.isEmpty ? nil : $0
                    }))
                }
                Section("Stock") {
                    #if !os(Android)
                    Stepper(value: $item.quantity, in: 0...1_000_000) {
                        Text("Quantity: \(item.quantity)")
                    }
                    Stepper(value: $item.reorderThreshold, in: 0...1_000_000) {
                        Text("Reorder threshold: \(item.reorderThreshold)")
                    }
                    #else
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text("Quantity")
                            Spacer()
                            HStack(spacing: 10) {
                                IconChip(name: minusIcon)
                                    .onTapGesture {
                                        if item.quantity > 0 {
                                            item.quantity -= 1
                                        }
                                    }
                                Text("\(item.quantity)")
                                    .frame(minWidth: 32, alignment: .center)
                                IconChip(name: plusIcon)
                                    .onTapGesture {
                                        if item.quantity < 1_000_000 {
                                            item.quantity += 1
                                        }
                                    }
                            }
                        }
                        HStack(spacing: 10) {
                            Text("Reorder threshold")
                            Spacer()
                            HStack(spacing: 10) {
                                IconChip(name: minusIcon)
                                    .onTapGesture {
                                        if item.reorderThreshold > 0 {
                                            item.reorderThreshold -= 1
                                        }
                                    }
                                Text("\(item.reorderThreshold)")
                                    .frame(minWidth: 32, alignment: .center)
                                IconChip(name: plusIcon)
                                    .onTapGesture {
                                        if item.reorderThreshold < 1_000_000 {
                                            item.reorderThreshold += 1
                                        }
                                    }
                            }
                        }
                    }
                    #endif
                }
                Section("Advanced") {
                    Picker("Storage", selection: Binding(get: {
                        item.storage ?? .ambient
                    }, set: {
                        item.storage = $0
                    })) {
                        Text("Ambient").tag(StorageType.ambient)
                        Text("Refrigerated").tag(StorageType.refrigerated)
                        Text("Frozen").tag(StorageType.frozen)
                    }
                    TextField("Shelf life (days)", value: $item.shelfLifeDays, format: .number)
                    TextField("Lead time (days)", value: $item.leadTimeDays, format: .number)
                    TextField("Par level", value: $item.parLevel, format: .number)
                    TextField("Reorder qty", value: $item.reorderQuantity, format: .number)
                    TextField("Cost per unit (cents)", value: $item.costPerUnitCents, format: .number)
                    TextField("Barcode", text: Binding(get: {
                        item.barcode ?? ""
                    }, set: {
                        item.barcode = $0.isEmpty ? nil : $0
                    }))
                    TextField("Supplier SKU", text: Binding(get: {
                        item.supplierSku ?? ""
                    }, set: {
                        item.supplierSku = $0.isEmpty ? nil : $0
                    }))
                    TextField("Safety stock", value: $item.safetyStock, format: .number)
                    TextField("Reserved qty", value: $item.reservedQuantity, format: .number)
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
}


