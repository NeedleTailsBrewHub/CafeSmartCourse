//
//  UITheme.swift
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
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Theme
extension Color {
    static let appColor = Color(red: 31/255, green: 128/255, blue: 230/255)
    static var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
    static var surfaceColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.controlBackgroundColor)
        #else
        return Color.white
        #endif
    }
    static var separatorColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.separatorColor)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}

enum AppSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppFont {
    static func largeTitle() -> Font { .custom("Roboto-Bold", size: 34) }
    static func title() -> Font { .custom("Roboto-Bold", size: 28) }
    static func title2() -> Font { .custom("Roboto-Bold", size: 22) }
    static func subtitle() -> Font { .custom("Roboto-Regular", size: 16) }
    static func headline() -> Font { .custom("Roboto-Medium", size: 17) }
    static func subheadline() -> Font { .custom("Roboto-Regular", size: 15) }
    static func body() -> Font { .custom("Roboto-Regular", size: 16) }
    static func callout() -> Font { .custom("Roboto-Regular", size: 15) }
    static func footnote() -> Font { .custom("Roboto-Medium", size: 12) }
    static func caption() -> Font { .custom("Roboto-Regular", size: 12) }
    static func caption2() -> Font { .custom("Roboto-Regular", size: 11) }
    static func button() -> Font { .custom("Roboto-Bold", size: 14) }
    static func iconLarge() -> Font { .custom("Roboto-Bold", size: 44) }
}

// MARK: - Reusable Components
struct CardContainer<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    // Content
    let content: Content
    
    // Configurables
    let padding: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color? // nil = no background
    let borderColor: Color?     // nil = no border
    let borderWidth: CGFloat
    let shadowEnabled: Bool
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowX: CGFloat
    let shadowY: CGFloat
    
    init(
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        backgroundColor: Color? = .clear,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0,
        shadowEnabled: Bool = true,
        shadowColor: Color = .clear,
        shadowRadius: CGFloat = 0,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowEnabled = shadowEnabled
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowX = shadowX
        self.shadowY = shadowY
        self.content = content()
    }
    
    var body: some View {
        let rounded = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let effectiveShadowColor = colorScheme == .dark ? shadowColor.opacity(0.25) : shadowColor
        
        content
            .padding(padding)
            .background(
                Group {
                    if let backgroundColor {
                        backgroundColor
                    }
                }
            )
            .clipShape(rounded)
            .overlay(
                Group {
                    if let borderColor, borderWidth > 0 {
                        rounded.strokeBorder(borderColor, lineWidth: borderWidth)
                    } else if borderWidth > 0 {
                        rounded.strokeBorder(Color.separatorColor, lineWidth: borderWidth)
                    }
                }
            )
            .shadow(
                color: shadowEnabled ? effectiveShadowColor : .clear,
                radius: shadowEnabled ? shadowRadius : 0,
                x: shadowEnabled ? shadowX : 0,
                y: shadowEnabled ? shadowY : 0
            )
    }
}

struct PrimaryButton: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    var systemImageName: String? = nil
    var fillWidth: Bool = false
    var action: @MainActor () -> Void
    
    init(
        title: String,
        systemImageName: String? = nil,
        fillWidth: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.fillWidth = fillWidth
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if let systemImageName {
                    Image(systemName: systemImageName)
                }
                Text(title)
                    .font(AppFont.button())
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .padding(.horizontal, fillWidth ? AppSpacing.lg : 0)
            .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
            .background(Color.appColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.appColor.opacity(colorScheme == .dark ? 0.2 : 0.35), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
    }
}

struct PrimaryNavigationLink<Destination: View>: View {
    let title: String
    var systemImageName: String? = nil
    let destination: Destination
    var fillWidth: Bool = false

    init(
        title: String,
        systemImageName: String? = nil,
        fillWidth: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.fillWidth = fillWidth
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: AppSpacing.sm) {
                if let systemImageName {
                    Image(systemName: systemImageName)
                }
                Text(title)
                    .font(AppFont.button())
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
            .background(Color.appColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.appColor.opacity(0.35), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Text Inputs

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = nil
    
    private let cornerRadius: CGFloat = 26
    
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .foregroundStyle(.secondary)
            }
            
            TextField(placeholder, text: $text)
                .font(AppFont.subtitle())
                .autocorrectionDisabled(true)
                .foregroundStyle(.primary)
            
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 14)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: colorScheme == .dark ? Color(.sRGBLinear, white: 1, opacity: 0.08) : Color(.sRGBLinear, white: 0, opacity: 0.12), radius: 18, x: 0, y: 8)
        #if os(macOS)
        .textFieldStyle(.plain)
        #endif
    }
}

struct AppSecureField: View {
    let placeholder: String
    @Binding var text: String
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = nil
    var showsRevealToggle: Bool = false

    @State var isRevealed: Bool = false

    private let cornerRadius: CGFloat = 26
#if os(Android)
    let secureIconOn = "visibility_off"
    let secureIconOff = "visibility_off"
#else
    let secureIconOn = "eye"
    let secureIconOff = "eye.slash"
#endif

    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .foregroundStyle(.secondary)
            }

            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .autocorrectionDisabled(true)
                        .font(AppFont.subtitle())
                        .foregroundStyle(.primary)
                } else {
                    SecureField(placeholder, text: $text)
                        .autocorrectionDisabled(true)
                        .font(AppFont.subtitle())
                        .foregroundStyle(.primary)
                }
            }

            if showsRevealToggle {
                Button(action: { isRevealed.toggle() }) {
                    Image(systemName: isRevealed ? secureIconOff : secureIconOn)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 14)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: colorScheme == .dark ? Color(.sRGBLinear, white: 1, opacity: 0.08) : Color(.sRGBLinear, white: 0, opacity: 0.12), radius: 18, x: 0, y: 8)
        #if os(macOS)
        .textFieldStyle(.plain)
        #endif
    }
}


// MARK: - Safe Geometry Helpers
@MainActor
private struct WidthPreferenceKey: @preconcurrency PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Safely captures the laid-out width of this view without affecting its layout.
    func captureWidth(in binding: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self) { binding.wrappedValue = $0 }
    }
}
