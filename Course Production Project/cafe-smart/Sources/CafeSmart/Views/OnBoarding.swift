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

struct OnBoarding: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
#endif
#if os(Android)
    let buttonImageName = "android_coffee_cup"
#else
    let buttonImageName = "cup.and.saucer.fill"
#endif
    
    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                HStack(alignment: .top) {
                    Image("Logo", bundle: .module)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .padding()
                    Spacer()
                }
                Spacer(minLength: AppSpacing.lg)
                
                CardContainer(padding: AppSpacing.md) {
                    Image("Welcome", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 220)
                        .accessibilityLabel("Team managing café with tablet")
                }
                .padding(.horizontal, AppSpacing.lg)
                
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Where Every Cup’s a Clever Choice")
                        .font(AppFont.title())
                        .foregroundStyle(Color.primary)
                    
                    Text("Efficient Orders, Seamless Reservations, Accurate Inventory—All at Your Fingertips")
                        .font(AppFont.subtitle())
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, AppSpacing.lg)
                
                Spacer()
                
                PrimaryNavigationLink(title: "Continue", fillWidth: true) {
                    AuthenticationView()
                }
                    .padding(.horizontal, AppSpacing.lg)
                
                Spacer(minLength: AppSpacing.lg)
            }
        }
        // Navigation is handled by ContentView switching to Home when didSignIn changes
#if os(iOS)
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            if value {
                dismiss()
            }
        }
#endif
    }
}
