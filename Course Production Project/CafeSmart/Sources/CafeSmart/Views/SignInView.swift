//
//  SignInView.swift
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

struct SignInView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @State var email: String = ""
    @State var password: String = ""
    @State var showSignupErrorAlert = false
    @FocusState var focusedField: Field?
    enum Field { case email, password }
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        Spacer(minLength: max(0, proxy.size.height * 0.06))
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
//                                .keyboardType(.emailAddress)
//                                .textContentType(.emailAddress)
//                                .focused($focusedField, equals: .email)
//                                .submitLabel(.next)
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
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit(signIn)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        
                        // Space before CTA
                        Spacer(minLength: AppSpacing.xl)
                        
                        PrimaryButton(title: "Sign In", systemImageName: nil, fillWidth: true) {
                            signIn()
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .padding(.horizontal, AppSpacing.lg)
                        
                        Spacer()
                        
                        HStack {
                            Button("Need an account? Sign up!") {
                                dismiss()
                            }
                            Spacer()
                            Button("Forgot your password?") {
                                print("Forgot password tapped")
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(AppSpacing.lg)
                    }
                    .frame(minHeight: proxy.size.height)
                    .alert(Text(password.isEmpty ? "Passwords is empty" : "email is empty"), isPresented: $showSignupErrorAlert){}
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func signIn() {
        if password.isEmpty || email.isEmpty {
            showSignupErrorAlert = true
            return
        }
        Task { @MainActor in
            do {
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                showSignupErrorAlert = true
            }
        }
    }
}
