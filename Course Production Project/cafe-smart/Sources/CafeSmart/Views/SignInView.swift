//
//  SignInView.swift
//  CafeSmart
//

import SwiftUI
import VenueSmartKit

struct SignInView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @State var email: String = ""
    @State var password: String = ""
    @State var showSignInErrorAlert = false
    @State var signInErrorMessage = "Please enter a valid email and password."
    @FocusState var focusedField: Field?
    enum Field { case email, password }
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
                                .font(AppFont.title())
                                .multilineTextAlignment(.center)
                            Text("Order ahead · skip the line · track pickup")
                                .font(AppFont.subheadline())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 480)

                        SurfacePanel {
                            VStack(spacing: AppSpacing.md) {
                                Text("Sign in")
                                    .font(AppFont.title2())
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit(signIn)
                            }
                        }
                        .frame(maxWidth: 480)

                        PrimaryButton(title: "Sign In", fillWidth: true) {
                            signIn()
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .frame(maxWidth: 480)

                        Spacer(minLength: AppSpacing.xl)

                        Button("Need an account? Sign up!") {
                            dismiss()
                        }
                        .font(AppFont.footnote())
                        .padding(.bottom, AppSpacing.lg)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    .alert(signInErrorMessage, isPresented: $showSignInErrorAlert) {}
                }
            }
            .background(Color.groupedBackgroundColor)
        }
        .onAppear { focusedField = .email }
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("@") && !password.isEmpty
    }

    private func signIn() {
        guard canSubmit else {
            signInErrorMessage = "Enter a valid email and password."
            showSignInErrorAlert = true
            return
        }
        Task { @MainActor in
            do {
                try await authenticationViewModel.login(email: email, password: password)
            } catch {
                signInErrorMessage = "Sign-in failed. Check your email and password."
                showSignInErrorAlert = true
            }
        }
    }
}
