//
//  AuthenticationView.swift
//  CafeSmart
//

import SwiftUI
import SkipFuse
import VenueSmartKit

struct AuthenticationView: View {

    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
#endif
    @State var email: String = ""
    @State var password: String = ""
    @State var confirmedPassword: String = ""
    @State var showSignupErrorAlert = false
    @State var signupErrorMessage = "Please complete all fields correctly."
    @State var showRegistrationErrorAlert = false
    @FocusState var focusedField: Field?
    enum Field {
        case email, password, confirmedPassword
    }
    let logger = Logger(subsystem: "com.needletails.CafeSmart", category: "AuthenticationView")
#if os(Android)
    private let emailIcon = "android_note"
    private let lockIcon = "lock.fill"
#else
    private let emailIcon = "envelope.fill"
    private let lockIcon = "lock.fill"
#endif

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: AppSpacing.xl)

                VStack(spacing: AppSpacing.sm) {
                    BrandAvatar(size: 96)
                    Text("Join CaféSmart")
                        .font(AppFont.title())
                        .multilineTextAlignment(.center)
                    Text("Create an account to order ahead and earn loyalty points.")
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 480)

                SurfacePanel {
                    VStack(spacing: AppSpacing.md) {
                        AppTextField(
                            placeholder: "Email",
                            text: $email,
                            leadingSystemImage: emailIcon
                        )
                        #if !os(Android) && !os(macOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textContentType(.username)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                        AppSecureField(
                            placeholder: "Password",
                            text: $password,
                            leadingSystemImage: lockIcon,
                            showsRevealToggle: true
                        )
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmedPassword }

                        AppSecureField(
                            placeholder: "Confirm Password",
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
                .frame(maxWidth: 480)

                PrimaryButton(title: "Sign Up", fillWidth: true) {
                    signUp()
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)
                .frame(maxWidth: 480)

                Spacer(minLength: AppSpacing.xl)

                NavigationLink("Already have an account? Sign In") {
                    SignInView()
                }
                .font(AppFont.footnote())
                .padding(.bottom, AppSpacing.xl)
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .alert(signupErrorMessage, isPresented: $showSignupErrorAlert) {}
            .alert("There was an error registering your account", isPresented: $showRegistrationErrorAlert) {}
#if os(iOS)
            .onChange(of: authenticationViewModel.didSignIn) { _, value in
                if value { dismiss() }
            }
#endif
        }
        .background(Color.groupedBackgroundColor)
        .onAppear { focusedField = .email }
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
            if !email.contains("@") {
                signupErrorMessage = "Enter a valid email address."
            } else if password.count <= 8 {
                signupErrorMessage = "Password must be longer than 8 characters."
            } else if password != confirmedPassword {
                signupErrorMessage = "Passwords do not match."
            } else {
                signupErrorMessage = "Please complete all fields correctly."
            }
            showSignupErrorAlert = true
            return
        }
        Task {
            do {
                try await authenticationViewModel.register(email: email, password: password)
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                showRegistrationErrorAlert = true
                logger.error("Error registering user: \(error)")
            }
        }
    }
}
