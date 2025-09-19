//
//  ProfileView.swift
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

struct ProfileView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var oldPassword: String = ""
    @State var newPassword: String = ""
    @State var confirmPassword: String = ""
    @State var showAlert = false
    @State var alertMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                SectionHeader(
                    title: "Profile",
                    subtitle: authenticationViewModel.user?.email ?? "")
                
                CardContainer(
                    padding: AppSpacing.lg,
                    cornerRadius: 16,
                    backgroundColor: .surfaceColor,
                    borderColor: .gray.opacity(0.15),
                    borderWidth: 1,
                    shadowEnabled: true,
                    shadowColor: .black.opacity(0.05),
                    shadowRadius: 10,
                    shadowX: 0,
                    shadowY: 6) {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Security")
                                .font(AppFont.headline())
                            HStack(spacing: AppSpacing.sm) { Image(systemName: "lock.fill"); AppSecureField(placeholder: "Current password", text: $oldPassword, showsRevealToggle: true) }
                            HStack(spacing: AppSpacing.sm) { Image(systemName: "lock.fill"); AppSecureField(placeholder: "New password", text: $newPassword, showsRevealToggle: true) }
                            HStack(spacing: AppSpacing.sm) { Image(systemName: "lock.fill"); AppSecureField(placeholder: "Confirm new password", text: $confirmPassword, showsRevealToggle: true) }
                            PrimaryButton(title: "Change password", fillWidth: true) {
                                changePassword()
                            }
                        }
                    }
                
                CardContainer(
                    padding: AppSpacing.lg,
                    cornerRadius: 16,
                    backgroundColor: .surfaceColor,
                    borderColor: .gray.opacity(0.15),
                    borderWidth: 1,
                    shadowEnabled: true,
                    shadowColor: .black.opacity(0.05),
                    shadowRadius: 10,
                    shadowX: 0,
                    shadowY: 6) {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Account")
                                .font(AppFont.headline())
                            PrimaryButton(title: "Sign out", fillWidth: true) {
                                signOut()
                            }
                            PrimaryButton(title: "Delete account", fillWidth: true) {
                                deleteAccount()
                            }
                        }
                    }
            }
            .padding()
        }
        .alert(alertMessage, isPresented: $showAlert) { }
        .navigationTitle("Profile")
    }
    
    private func changePassword() {
        guard !oldPassword.isEmpty,
              !newPassword.isEmpty,
              newPassword == confirmPassword,
              let email = authenticationViewModel.user?.email else {
            alertMessage = "Please fill all fields and ensure passwords match."; showAlert = true; return
        }
        Task { @MainActor in
            do {
                try await authenticationViewModel.updatePassword(
                    email: email,
                    oldPassword: oldPassword,
                    newPassword: newPassword)
                
                alertMessage = "Password updated"; showAlert = true
                oldPassword = ""
                newPassword = ""
                confirmPassword = ""
                
            } catch {
                alertMessage = "Failed to update password"; showAlert = true
            }
        }
    }
    
    private func signOut() {
        authenticationViewModel.signOut()
        dismiss()
    }
    
    private func deleteAccount() {
        authenticationViewModel.deleteAccountLocally()
        dismiss()
    }
}


