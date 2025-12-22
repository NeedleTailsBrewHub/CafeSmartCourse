//
//  MenuView.swift
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

struct MenuView: View {
    @Environment(MenuViewModel.self) var menuViewModel
    @State var items: [MenuItem] = []
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

                SectionHeader(title: "Menu", subtitle: "Today's offerings")
                LazyVStack(spacing: AppSpacing.md) {
                    if menuViewModel.isLoading {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity)
                    }
                    if items.isEmpty && !menuViewModel.isLoading {
                        Text("Menu is empty.").font(AppFont.subheadline()).foregroundStyle(.secondary)
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
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(AppFont.headline())
                                        if let desc = item.description, !desc.isEmpty { Text(desc).font(AppFont.footnote()).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Text(CurrencyHelper.dollars(fromCents: item.priceCents), format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(AppFont.body())
                                }
                                HStack(spacing: 8) {
                                    if let category = item.category, !category.isEmpty {
                                        Text(category).font(AppFont.footnote()).padding(.horizontal, 10).padding(.vertical, 4).background(Color.gray.opacity(0.12)).clipShape(Capsule())
                                    }
                                    if let allergens = item.allergens, !allergens.isEmpty {
                                        Text("Allergens \(allergens.count)").font(AppFont.footnote()).padding(.horizontal, 10).padding(.vertical, 4).background(Color.orange.opacity(0.12)).clipShape(Capsule())
                                    }
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
        .onAppear { items = menuViewModel.items.filter { $0.isAvailable } }
        .task {
            do { try await menuViewModel.fetchMenu(); items = menuViewModel.items.filter { $0.isAvailable } } catch { menuViewModel.errorMessage = "Failed to load menu." }
        }
        .refreshable {
            do { try await menuViewModel.fetchMenu(); items = menuViewModel.items.filter { $0.isAvailable } } catch { menuViewModel.errorMessage = "Failed to refresh menu." }
        }
        .navigationTitle("Menu")
    }
}


