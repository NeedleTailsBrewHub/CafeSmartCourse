//
//  ContentView.swift
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
import ConnectionManagerKit

struct ContentView: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(BusinessViewModel.self) var businessViewModel
    @Environment(InventoryViewModel.self) var inventoryViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(ReservationViewModel.self) var reservationViewModel
    @Environment(SocketReceiver.self) var socketReceiver
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var didSignIn: Bool = false
    
    var body: some View {
        Group {
            if didSignIn {
                #if os(macOS)
                MacHomeView()
                    .task {
                        Task.detached {
                            try await businessViewModel.fetchConfig()
                            try await inventoryViewModel.fetchInventory()
                            try await menuViewModel.fetchMenu()
                            try await orderViewModel.fetchOrders()
                            try await reservationViewModel.fetchReservations()
                        }
                    }
                #else
                HomeView()
                    .task {
                        Task.detached {
                            try await businessViewModel.fetchConfig()
                            try await inventoryViewModel.fetchInventory()
                            try await menuViewModel.fetchMenu()
                            try await orderViewModel.fetchOrders()
                            try await reservationViewModel.fetchReservations()
                        }
                    }
                #endif
            } else {
                OnBoarding()
            }
        }
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            didSignIn = value
        }
        .onDisappear {
            // Prevent queued banners from trying to render across view transitions
            appNotificationCenter.reset()
        }
    }
}
