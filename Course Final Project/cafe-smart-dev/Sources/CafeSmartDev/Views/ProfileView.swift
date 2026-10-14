//
//  ProfileView.swift
//  CafeSmartDev
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

struct ProfileView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @Environment(\.dismiss) var dismiss
    
    @State var oldPassword: String = ""
    @State var newPassword: String = ""
    @State var confirmPassword: String = ""
    @State var showAlert = false
    @State var alertMessage = ""
    @State var showDeleteConfirm = false
    
    var body: some View {
        ScreenCanvas {
            HStack(spacing: AppSpacing.md) {
                BrandAvatar(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(authenticationViewModel.user?.name
                         ?? authenticationViewModel.user?.email
                         ?? "Guest")
                        .font(AppFont.title2())
                        .lineLimit(1)
                    Text(authenticationViewModel.user?.email ?? "")
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                    if authenticationViewModel.user?.isAdmin == true {
                        StatusChip(text: "Merchant", tone: .accent)
                    }
                }
                Spacer(minLength: 0)
            }

            PanelSection(title: "Security", subtitle: "Update your password") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    AppSecureField(placeholder: "Current password", text: $oldPassword, showsRevealToggle: true)
                    AppSecureField(placeholder: "New password", text: $newPassword, showsRevealToggle: true)
                    AppSecureField(placeholder: "Confirm new password", text: $confirmPassword, showsRevealToggle: true)
                    PrimaryButton(title: "Change password", fillWidth: true) {
                        changePassword()
                    }
                }
            }

            PanelSection(title: "Account", subtitle: "Session and data") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SecondaryButton(title: "Sign out", fillWidth: true) {
                        signOut()
                    }
                    DestructiveButton(title: "Delete account", fillWidth: true) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .alert(alertMessage, isPresented: $showAlert) { }
        .confirmationDialog(
            "Delete your account? This cannot be undone.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Profile")
    }
    
    private func changePassword() {
        guard !oldPassword.isEmpty,
              !newPassword.isEmpty,
              newPassword == confirmPassword,
              let email = authenticationViewModel.user?.email else {
            alertMessage = "Please fill all fields and ensure passwords match."
            showAlert = true
            return
        }
        Task { @MainActor in
            do {
                try await authenticationViewModel.updatePassword(
                    email: email,
                    oldPassword: oldPassword,
                    newPassword: newPassword)
                
                alertMessage = "Password updated"
                showAlert = true
                oldPassword = ""
                newPassword = ""
                confirmPassword = ""
                
            } catch {
                alertMessage = "Failed to update password"
                showAlert = true
            }
        }
    }
    
    private func signOut() {
        authenticationViewModel.signOut()
        appNotificationCenter.reset()
        dismiss()
    }
    
    private func deleteAccount() {
        authenticationViewModel.deleteAccountLocally()
        appNotificationCenter.reset()
        dismiss()
    }
}
