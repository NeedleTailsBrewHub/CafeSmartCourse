//
//  Onboarding.swift
//  CafeSmartDev
//

import SwiftUI

struct Onboarding: View {

    @Environment(AuthenticationViewModel.self) var authenticationViewModel
#if os(iOS)
    @Environment(\.dismiss) var dismiss
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                Color.groupedBackgroundColor.ignoresSafeArea()

                Image("Welcome", bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.16)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer(minLength: AppSpacing.xl)

                    VStack(spacing: AppSpacing.md) {
                        BrandAvatar(size: 104)

                        Text("CaféSmart")
                            .font(AppFont.largeTitle())
                            .multilineTextAlignment(.center)

                        Text("Order ahead. Pick up when it’s ready.")
                            .font(AppFont.title2())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, AppSpacing.lg)

                        Text("A calm café ordering experience for guests—and the tools merchants need behind the counter.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    Spacer()

                    VStack(spacing: AppSpacing.md) {
                        featureLine(
                            icon: featureOrderIcon,
                            title: "Build your order",
                            detail: "Browse the board, customize sizes, and checkout for pickup."
                        )
                        featureLine(
                            icon: featureTrackIcon,
                            title: "Track every ticket",
                            detail: "See when your order is received, preparing, or ready."
                        )
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.lg)

                    PrimaryNavigationLink(title: "Get started", fillWidth: true) {
                        AuthenticationView()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
#if os(iOS)
        .onChange(of: authenticationViewModel.didSignIn) { _, value in
            if value { dismiss() }
        }
#endif
    }

#if os(Android)
    private var featureOrderIcon: String { "orders" }
    private var featureTrackIcon: String { "orders" }
#else
    private var featureOrderIcon: String { "cart.fill" }
    private var featureTrackIcon: String { "tray.full.fill" }
#endif

    @ViewBuilder
    private func featureLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(Color.appColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                AppImage(name: icon)
                    .foregroundStyle(Color.appColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.headline())
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(Color.surfaceColor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
        )
    }
}
