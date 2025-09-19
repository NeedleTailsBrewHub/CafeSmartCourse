//
//  AuthenticationView.swift
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
import SkipFuse

struct AuthenticationView: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
#endif
    @State var email: String = ""
    @State var password: String = ""
    @State var confirmedPassword: String = ""
    @State var showSignupErrorAlert = false
    @State var showRegistrationErrorAlert = false
    @FocusState var focusedField: Field?
    enum Field {
        case email, password, confirmedPassword
    }
    let logger = Logger(subsystem: "my.subsystem", category: "AuthenticationView")
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: AppSpacing.xl)
                
                // Centered header
                VStack(spacing: AppSpacing.sm) {
                    HStack {
                        Spacer()
                        Image("Logo", bundle: .module)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                            .padding()
                        Spacer()
                    }
                    Text("CaféSmart")
                        .font(AppFont.title())
                        .multilineTextAlignment(.center)
                    Text("Where Every Cup’s a Clever Choice")
                        .font(AppFont.subtitle())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)
                
                // Centered form
                VStack(spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.primary)
                        AppTextField(
                            placeholder: "Email",
                            text: $email)
//                        .keyboardType(.emailAddress)
//                        .textContentType(.emailAddress)
//                        .focused($focusedField, equals: .email)
//                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    }
                    
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.primary)
                        AppSecureField(
                            placeholder: "Password",
                            text: $password,
                            showsRevealToggle: true
                        )
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { focusedField = .confirmedPassword }
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.primary)
                        AppSecureField(
                            placeholder: "Confirm Password",
                            text: $confirmedPassword,
                            showsRevealToggle: true
                        )
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmedPassword)
                        .submitLabel(.go)
                        .onSubmit(signUp)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                
                // Space before CTA
                Spacer(minLength: AppSpacing.xl)
                
                PrimaryButton(title: "Sign Up", systemImageName: nil, fillWidth: true) {
                    signUp()
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)
                .padding(.horizontal, AppSpacing.lg)
                
                Spacer()
                
                // Bottom footer centered
                NavigationLink("Already have an account? Sign In") {
                    SignInView()
                }
                .font(.footnote.weight(.semibold))
                .padding(.bottom, AppSpacing.xl)
            }
            .alert(Text(password.isEmpty ? "Passwords is empty" : "Email is empty"), isPresented: $showSignupErrorAlert){}
            .alert("There was an error registering your account", isPresented: $showRegistrationErrorAlert){}
            // Navigation is handled by ContentView switching to Home when didSignIn changes
#if os(iOS)
            .onChange(of: authenticationViewModel.didSignIn) { _, value in
                if value { dismiss() }
            }
#endif
        }
    }
    
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }
    
    private func signUp() {
        if password != confirmedPassword || email.isEmpty, !email.contains("@"), password.count <= 8 {
            showSignupErrorAlert = true
            return
        }
        Task {
            do {
                try await authenticationViewModel.register(email: email, password: password)
                // After registration, attempt login to populate user and trigger navigation
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                showRegistrationErrorAlert = true
                logger.error("Error registering user: \(error)")
            }
        }
    }
}
