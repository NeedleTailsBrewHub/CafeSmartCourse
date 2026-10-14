//
//  MenuView.swift
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

struct MenuView: View {
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var items: [MenuItem] = []
    @State var selectedCategory: String? = nil
    @State var searchQuery = ""
    @State var itemToCustomize: MenuItem? = nil

#if os(Android)
    private let emptyIcon = "android_coffee_cup"
#else
    private let emptyIcon = "cup.and.saucer.fill"
#endif

    private var categories: [String] {
        let values = items.compactMap(\.category).filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }

    private var filteredItems: [MenuItem] {
        let categoryItems: [MenuItem]
        if let selectedCategory, !selectedCategory.isEmpty {
            categoryItems = items.filter { $0.category == selectedCategory }
        } else {
            categoryItems = items
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categoryItems }
        return categoryItems.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var groupedItems: [(String, [MenuItem])] {
        let source = filteredItems
        var buckets: [String: [MenuItem]] = [:]
        for item in source {
            let key = item.category?.isEmpty == false ? item.category! : "More"
            buckets[key, default: []].append(item)
        }
        return buckets.keys.sorted().map { key in
            (key, buckets[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        ScreenCanvas {
            SectionHeader(
                title: "Today’s board",
                subtitle: "What’s available for guests right now")

            AppTextField(
                placeholder: "Search the menu",
                text: $searchQuery,
                leadingSystemImage: searchIcon
            )

            if !categories.isEmpty {
                CategoryChipBar(categories: categories, selection: $selectedCategory)
            }

            if let err = menuViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            if menuViewModel.isLoading {
                LoadingBlock()
            } else if items.isEmpty {
                EmptyState(
                    title: "Menu is empty",
                    subtitle: "Available items will show up after sync.",
                    systemImage: emptyIcon
                )
            } else if filteredItems.isEmpty {
                EmptyState(
                    title: "Nothing in this category",
                    subtitle: "Try another filter or pull to refresh.",
                    systemImage: emptyIcon
                )
            } else {
                ForEach(groupedItems, id: \.0) { category, rows in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(category)
                            .font(AppFont.headline())
                            .foregroundStyle(.secondary)
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(rows) { item in
                                MenuItemRow(
                                    item: item,
                                    showsAdd: true,
                                    addTitle: item.sizeOptions?.isEmpty == false ? "Choose" : "Add"
                                ) {
                                    if item.sizeOptions?.isEmpty == false {
                                        itemToCustomize = item
                                    } else {
                                        cartViewModel.add(item: item)
                                        appNotificationCenter.show(
                                            "\(item.name) added to your cart.",
                                            iconSystemName: successIcon,
                                            duration: 2.0
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { items = menuViewModel.items.filter { $0.isAvailable } }
        .task {
            do {
                try await menuViewModel.fetchMenu()
                items = menuViewModel.items.filter { $0.isAvailable }
            } catch {
                menuViewModel.errorMessage = "Failed to load menu."
            }
        }
        .refreshable {
            do {
                try await menuViewModel.fetchMenu()
                items = menuViewModel.items.filter { $0.isAvailable }
            } catch {
                menuViewModel.errorMessage = "Failed to refresh menu."
            }
        }
        .navigationTitle("Menu")
        .sheet(item: $itemToCustomize) { item in
            AddToCartSheet(item: item) { quantity, size in
                cartViewModel.add(item: item, quantity: quantity, size: size)
                appNotificationCenter.show(
                    "\(item.name) added to your cart.",
                    iconSystemName: successIcon,
                    duration: 2.0
                )
            }
        }
    }

    private var searchIcon: String {
        #if os(Android)
        "android_note"
        #else
        "magnifyingglass"
        #endif
    }

    private var successIcon: String {
        #if os(Android)
        "orders"
        #else
        "checkmark.circle.fill"
        #endif
    }
}
