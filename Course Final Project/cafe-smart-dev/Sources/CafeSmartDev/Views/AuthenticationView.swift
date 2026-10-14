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

struct AuthenticationView: View {

    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @State var email: String = ""
    @State var password: String = ""
    @State var confirmedPassword: String = ""
    @State var showSignupErrorAlert = false
    @State var showRegistrationErrorAlert = false
    @FocusState var focusedField: Field?
    @Environment(\.dismiss) var dismiss

#if os(Android)
    private let emailIcon = "android_note"
    private let lockIcon = "lock.fill"
#else
    private let emailIcon = "envelope.fill"
    private let lockIcon = "lock.fill"
#endif

    enum Field {
        case email, password, confirmedPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: AppSpacing.lg)

                VStack(spacing: AppSpacing.sm) {
                    BrandAvatar(size: 96)
                    Text("Create your account")
                        .font(AppFont.title2())
                        .multilineTextAlignment(.center)
                    Text("Join your café workspace")
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
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            focusedField = .confirmedPassword
                        }

                        AppSecureField(
                            placeholder: "Confirm password",
                            text: $confirmedPassword,
                            leadingSystemImage: lockIcon,
                            showsRevealToggle: true
                        )
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmedPassword)
                        .submitLabel(.go)
                        .onSubmit(signUp)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                PrimaryButton(title: "Sign Up", fillWidth: true) {
                    signUp()
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)
                .padding(.horizontal, AppSpacing.lg)

                NavigationLink("Already have an account? Sign In") {
                    SignInView()
                }
                .font(AppFont.footnote())
                .padding(.bottom, AppSpacing.xl)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .alert(
                Text(password.isEmpty ? "Password is empty" : "Enter a valid email"),
                isPresented: $showSignupErrorAlert
            ) {}
            .alert("There was an error registering your account", isPresented: $showRegistrationErrorAlert) {}
        }
        .background(Color.groupedBackgroundColor)
        .onChange(of: authenticationViewModel.didSignIn) { _, newValue in
            if newValue {
                dismiss()
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.contains("@")
            && password.count > 8
            && password == confirmedPassword
    }

    private func signUp() {
        guard canSubmit else {
            showSignupErrorAlert = true
            return
        }

        Task {
            do {
                try await authenticationViewModel.registration(email: email, password: password)
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                showRegistrationErrorAlert = true
                logger.info("Error registering: \(error)")
            }
        }
    }
}
