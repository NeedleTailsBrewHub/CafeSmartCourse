//
//  ProfileView.swift
//  CafeSmart
//
//  Account settings — avatar header + grouped panels matching marketplace home.
//

import SwiftUI
import VenueSmartKit

struct ProfileView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter
    @Environment(\.dismiss) var dismiss
    @Environment(HomeNavigator.self) var homeNavigator

    @State var loyalty = LoyaltyViewModel()
    @State var editName: String = ""
    @State var editEmail: String = ""
    @State var isSavingProfile = false
    @State var oldPassword: String = ""
    @State var newPassword: String = ""
    @State var confirmPassword: String = ""
    @State var showAlert = false
    @State var alertMessage = ""
    @State var showDeleteConfirm = false
    @State var isDeleting = false
    @State var isSigningOut = false

#if os(Android)
    private let lockIcon = "lock.fill"
    private let reserveTableIcon = "android_calendar"
#else
    private let lockIcon = "lock.fill"
    private let reserveTableIcon = "calendar"
#endif

    private var profileDirty: Bool {
        let currentName = authenticationViewModel.user?.name ?? ""
        let currentEmail = authenticationViewModel.user?.email ?? ""
        return editName.trimmingCharacters(in: .whitespacesAndNewlines) != currentName
            || editEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != currentEmail.lowercased()
    }

    private var displayName: String {
        authenticationViewModel.user?.name
            ?? authenticationViewModel.user?.email
            ?? "Guest"
    }

    private var usesBusinessSplitShell: Bool {
        BusinessShellPolicy.usesSplitShell(
            user: authenticationViewModel.user,
            idiom: BusinessShellPolicy.currentIdiom())
    }

    private var supportLabel: some View {
        HStack(spacing: AppSpacing.md) {
            AppImage(name: "questionmark.circle.fill")
                .font(AppFont.title2())
                .foregroundStyle(Color.appColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Help & support")
                    .font(AppFont.headline())
                Text("Send a message or browse FAQ")
                    .font(AppFont.footnote())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        ScreenCanvas {
            SurfacePanel(padding: 0, tone: .accent) {
                HStack(spacing: AppSpacing.md) {
                    BrandAvatar(size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account")
                            .font(AppFont.caption())
                            .foregroundStyle(Color.appColor)
                        Text(displayName)
                            .font(AppFont.title2())
                            .lineLimit(1)
                        Text(authenticationViewModel.user?.email ?? "")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if authenticationViewModel.user?.isAdmin == true {
                                StatusChip(text: "Merchant", tone: .accent)
                            } else {
                                StatusChip(text: "Customer", tone: .neutral)
                            }
                            if let account = loyalty.account {
                                StatusChip(text: "\(account.points) pts", tone: .success)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.md)
            }

            PanelSection(title: "Dining", subtitle: "Book seating for pickup or dine-in") {
                // Split shell (Mac / admin iPad): switch sidebar selection.
                // Phone: push onto the Settings tab NavigationStack.
                if usesBusinessSplitShell {
                    Button {
                        homeNavigator.open(.reserveTable)
                    } label: {
                        reserveTableLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        TableReservationView()
                    } label: {
                        reserveTableLabel
                    }
                    .buttonStyle(.plain)
                }
            }

            PanelSection(title: "Help", subtitle: "Contact the café about orders or your account") {
                if usesBusinessSplitShell {
                    Button {
                        homeNavigator.open(.support)
                    } label: {
                        supportLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        SupportView()
                    } label: {
                        supportLabel
                    }
                    .buttonStyle(.plain)
                }
            }

            PanelSection(title: "Account details", subtitle: "Name and email used on orders") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    AppTextField(placeholder: "Display name", text: $editName)
                    AppTextField(placeholder: "Email", text: $editEmail)
                    PrimaryButton(
                        title: isSavingProfile ? "Saving…" : "Save changes",
                        fillWidth: true
                    ) {
                        Task { await saveProfile() }
                    }
                    .disabled(isSavingProfile || !profileDirty)
                    .opacity(profileDirty ? 1 : 0.55)
                }
            }

            PanelSection(title: "Loyalty", subtitle: "Earn on paid items · redeem free items at checkout") {
                if loyalty.isLoading {
                    LoadingBlock()
                } else if let account = loyalty.account {
                    AdaptiveDetailRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(account.points) points")
                                .font(AppFont.title2())
                                .foregroundStyle(Color.appColor)
                            Text("At checkout, toggle “use my points” to make eligible items free.")
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                        }
                    } actions: {
                        StatusChip(text: account.tier.capitalized, tone: .accent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Join free to earn points when loyalty is enabled — redeem at checkout on eligible items.")
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                        PrimaryButton(
                            title: loyalty.isMutating ? "Joining…" : "Join loyalty",
                            fillWidth: true
                        ) {
                            Task { await joinLoyalty() }
                        }
                        .disabled(loyalty.isMutating)
                    }
                }
            }

            PanelSection(title: "Security", subtitle: "Update your password") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    AppSecureField(
                        placeholder: "Current password",
                        text: $oldPassword,
                        leadingSystemImage: lockIcon,
                        showsRevealToggle: true
                    )
                    AppSecureField(
                        placeholder: "New password",
                        text: $newPassword,
                        leadingSystemImage: lockIcon,
                        showsRevealToggle: true
                    )
                    AppSecureField(
                        placeholder: "Confirm new password",
                        text: $confirmPassword,
                        leadingSystemImage: lockIcon,
                        showsRevealToggle: true
                    )
                    PrimaryButton(title: "Change password", fillWidth: true) {
                        changePassword()
                    }
                }
            }

            PanelSection(title: "Session", subtitle: "Sign out or remove your account") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SecondaryButton(
                        title: isSigningOut ? "Signing out…" : "Sign out",
                        fillWidth: true
                    ) {
                        signOut()
                    }
                    .disabled(isSigningOut)
                    DestructiveButton(
                        title: isDeleting ? "Deleting…" : "Delete account",
                        fillWidth: true
                    ) {
                        showDeleteConfirm = true
                    }
                    .disabled(isDeleting)
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
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear { loadProfileFields() }
        .task {
            if let id = authenticationViewModel.user?.id {
                await loyalty.fetchLoyalty(userId: id)
            }
        }
    }

    private var reserveTableLabel: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(Color.appColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                AppImage(name: reserveTableIcon)
                    .foregroundStyle(Color.appColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reserve a table")
                    .font(AppFont.headline())
                    .foregroundStyle(.primary)
                Text("See open slots and manage bookings")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
#if os(Android)
            Text("›")
                .font(AppFont.title2())
                .foregroundStyle(.secondary)
#else
            AppImage(name: "chevron.right")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
#endif
        }
    }

    private func loadProfileFields() {
        editName = authenticationViewModel.user?.name ?? ""
        editEmail = authenticationViewModel.user?.email ?? ""
    }

    @MainActor
    private func joinLoyalty() async {
        guard let id = authenticationViewModel.user?.id else { return }
        do {
            _ = try await loyalty.enroll(userId: id)
            appNotificationCenter.show(
                "You're in loyalty — points start on your next order",
                iconSystemName: "star.fill",
                duration: 3.0)
        } catch {
            alertMessage = "Could not join loyalty. Try again."
            showAlert = true
        }
    }

    @MainActor
    private func saveProfile() async {
        guard !isSavingProfile else { return }
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = editEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            alertMessage = "Enter a valid email address."
            showAlert = true
            return
        }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            try await authenticationViewModel.updateProfile(
                name: name.isEmpty ? nil : name,
                email: email)
            loadProfileFields()
            appNotificationCenter.show(
                "Profile updated",
                iconSystemName: "checkmark.circle.fill",
                duration: 2.5)
        } catch {
            if case AuthenticationViewModel.Errors.failedRequest(let code) = error, code == 409 {
                alertMessage = "That email is already in use."
            } else {
                alertMessage = "Could not update profile. Try again."
            }
            showAlert = true
        }
    }

    private func changePassword() {
        guard !oldPassword.isEmpty,
              !newPassword.isEmpty,
              newPassword.count >= 8,
              newPassword == confirmPassword,
              let email = authenticationViewModel.user?.email else {
            alertMessage = "Fill all fields, use 8+ characters, and match confirm password."
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
                if case AuthenticationViewModel.Errors.failedRequest(let code) = error, code == 401 {
                    alertMessage = "Current password is incorrect."
                } else {
                    alertMessage = "Failed to update password"
                }
                showAlert = true
            }
        }
    }

    private func signOut() {
        Task { @MainActor in
            isSigningOut = true
            defer { isSigningOut = false }
            do {
                try await authenticationViewModel.logout()
            } catch {
                authenticationViewModel.signOut()
            }
            appNotificationCenter.reset()
            dismiss()
        }
    }

    private func deleteAccount() {
        Task { @MainActor in
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await authenticationViewModel.deleteAccount()
                appNotificationCenter.reset()
                dismiss()
            } catch {
                alertMessage = "Failed to delete account."
                showAlert = true
            }
        }
    }
}
