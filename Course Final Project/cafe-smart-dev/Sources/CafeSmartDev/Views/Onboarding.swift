//
//  SwiftUIView.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/8/25.
//

import SwiftUI

struct Onboarding: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
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
                        .accessibilityLabel("Team managing café")
                }
                .padding(.horizontal, AppSpacing.lg)
                
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Where Every Cup's a Clever Choice")
                        .font(AppFont.title())
                        .foregroundStyle(Color.primary)
                    
                    Text("Where Every Cup's a Clever Choice")
                        .font(AppFont.subtitle())
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, AppSpacing.lg)
                
                PrimaryNavigationLink(title: "Continue", fillWidth: true) {
                    AuthenticationView()
                }
                .padding(.horizontal, AppSpacing.lg)
                
                Spacer(minLength: AppSpacing.lg)
                
            }
        }
#if os(iOS)
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            if value {
                dismiss()
            }
        }
#endif
    }
}
