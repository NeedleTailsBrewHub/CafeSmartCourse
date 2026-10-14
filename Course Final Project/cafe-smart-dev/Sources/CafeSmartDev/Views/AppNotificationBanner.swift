//
//  AppNotificationBanner.swift
//  CafeSmartDev
//

import SwiftUI

struct AppNotificationBanner: View {
    @Environment(AppNotificationCenter.self) var center
    
    var body: some View {
        ZStack {
            if center.isPresented {
                #if os(macOS)
                HStack {
                    Spacer()
                    banner
                        .frame(width: 340)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                }
                #else
                banner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1000)
                #endif
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: center.isPresented)
#if os(macOS)
        .padding(.top, 8)
#elseif os(Android)
        .padding(.top, 28)
#else
        .padding(.top, 12)
        .safeAreaPadding(.top, 4)
#endif
    }
    
    private var bannerTint: Color {
        let icon = center.iconSystemName ?? ""
        if icon.contains("xmark") || icon.contains("exclamation") {
            return Color.orange.opacity(0.95)
        }
        if icon.contains("trash") {
            return Color.red.opacity(0.9)
        }
        if icon.contains("checkmark") || icon.contains("seal") {
            return Color.appColor
        }
        return Color.black.opacity(0.88)
    }

    private var banner: some View {
        HStack(spacing: AppSpacing.sm) {
            if let icon = center.iconSystemName, !icon.isEmpty {
                AppImage(name: icon)
                    .foregroundStyle(.white)
            }
            Text(center.message)
                .font(AppFont.footnote())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(bannerTint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(center.message)
    }
}
