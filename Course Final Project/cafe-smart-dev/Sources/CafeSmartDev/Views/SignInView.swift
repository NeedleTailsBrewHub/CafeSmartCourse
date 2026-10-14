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
    enum Field {
        case email, password
    }
    @Environment(\.dismiss) var dismiss
#if os(Android)
    private let emailIcon = "android_note"
    private let lockIcon = "lock.fill"
#else
    private let emailIcon = "envelope.fill"
    private let lockIcon = "lock.fill"
#endif

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        Spacer(minLength: max(0, proxy.size.height * 0.08))

                        VStack(spacing: AppSpacing.sm) {
                            BrandAvatar(size: 96)
                            Text("Welcome back")
                                .font(AppFont.title2())
                                .multilineTextAlignment(.center)
                            Text("Sign in to your café workspace")
                                .font(AppFont.subheadline())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        SurfacePanel {
                            VStack(spacing: AppSpacing.md) {
                                AppTextField(
                                    placeholder: "Email",
                                    text: $email,
                                    leadingSystemImage: emailIcon
                                )
                                .focused($focusedField, equals: .email)
                                .onSubmit { focusedField = .password }

                                AppSecureField(
                                    placeholder: "Password",
                                    text: $password,
                                    leadingSystemImage: lockIcon,
                                    showsRevealToggle: true
                                )
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit(signIn)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        PrimaryButton(title: "Sign In", fillWidth: true) {
                            signIn()
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .padding(.horizontal, AppSpacing.lg)

                        Spacer()

                        Button("Need an account? Sign up!") {
                            dismiss()
                        }
                        .font(AppFont.footnote())
                        .padding(AppSpacing.lg)
                    }
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    .alert("Enter a valid email and password.", isPresented: $showSignupErrorAlert) {}
                }
            }
            .background(Color.groupedBackgroundColor)
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

        Task {
            do {
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                showSignupErrorAlert = true
            }
        }
    }
}
