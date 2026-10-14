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
import VenueSmartKit

struct ContentView: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(BusinessViewModel.self) var businessViewModel
    @Environment(TagViewModel.self) var tagViewModel
    @Environment(TeamViewModel.self) var teamViewModel
    @Environment(SeatingViewModel.self) var seatingViewModel
    @Environment(RecipesViewModel.self) var recipesViewModel
    @Environment(SupportViewModel.self) var supportViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @Environment(ReservationViewModel.self) var reservationViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(InventoryViewModel.self) var inventoryViewModel
    @Environment(CartViewModel.self) var cartViewModel
    @Environment(SocketReceiver.self) var socketReceiver
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @State var didSignIn: Bool = false
    @State var isRestoringSession: Bool = true
    
    var body: some View {
        Group {
            if isRestoringSession {
                ZStack {
                    Color.groupedBackgroundColor.ignoresSafeArea()
                    ProgressView("Signing you in…")
                }
            } else if didSignIn {
                Group {
                    if BusinessShellPolicy.usesSplitShell(
                        user: authenticationViewModel.user,
                        idiom: BusinessShellPolicy.currentIdiom()
                    ) {
                        BusinessHomeView()
                    } else {
                        HomeView()
                    }
                }
                .task { await bootstrapAfterLogin() }
            } else {
                OnBoarding()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: didSignIn)
        .task {
            await authenticationViewModel.restoreSessionIfNeeded()
            didSignIn = authenticationViewModel.didSignIn
            if didSignIn {
                cartViewModel.bind(userId: authenticationViewModel.user?.id)
            }
            isRestoringSession = false
        }
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            withAnimation(.easeInOut(duration: 0.25)) {
                didSignIn = value
            }
            if value {
                cartViewModel.bind(userId: authenticationViewModel.user?.id)
            } else {
                clearSessionState()
            }
        }
        .onChange(of: authenticationViewModel.user?.id) { _, userId in
            if didSignIn {
                cartViewModel.bind(userId: userId)
            }
        }
        .onDisappear {
            // Prevent queued banners from trying to render across view transitions
            appNotificationCenter.reset()
        }
    }

    @MainActor
    private func bootstrapAfterLogin() async {
        cartViewModel.bind(userId: authenticationViewModel.user?.id)
        do {
            try await businessViewModel.fetchRuntime()
            try await businessViewModel.fetchConfig()
            try await tagViewModel.refreshCatalog()
        } catch {
            logger.error("Post-login bootstrap failed: \(error)")
        }
    }

    @MainActor
    private func clearSessionState() {
        orderViewModel.resetSession()
        reservationViewModel.resetSession()
        menuViewModel.resetSession()
        inventoryViewModel.resetSession()
        cartViewModel.resetSession()
        teamViewModel.resetSession()
        tagViewModel.resetSession()
        seatingViewModel.resetSession()
        recipesViewModel.resetSession()
        businessViewModel.resetSession()
        supportViewModel.resetSession()
        appNotificationCenter.reset()
    }
}
