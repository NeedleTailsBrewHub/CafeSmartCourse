//
//  OnBoarding.swift
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

struct OnBoarding: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
#endif
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.groupedBackgroundColor.ignoresSafeArea()
                Image("Welcome", bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.18)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.lg) {
                    Spacer(minLength: AppSpacing.xl)
                    BrandAvatar(size: 104)

                    Text("CaféSmart")
                        .font(AppFont.largeTitle())
                        .multilineTextAlignment(.center)

                    Text("Order ahead. Skip the line.")
                        .font(AppFont.title2())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)

                    Text("Pickup coffee and food, track orders, and run the café floor.")
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)

                    Spacer()

                    PrimaryNavigationLink(title: "Continue", fillWidth: true) {
                        AuthenticationView()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
        }
#if os(iOS)
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            if value { dismiss() }
        }
#endif
    }
}
