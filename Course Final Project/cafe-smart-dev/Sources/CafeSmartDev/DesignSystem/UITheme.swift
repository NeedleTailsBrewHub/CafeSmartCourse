//
//  UITheme.swift
//  CafeSmartDev
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
    /// Brand accent — café teal that reads well in system light/dark chrome.
    static let appColor = Color(red: 36/255, green: 110/255, blue: 118/255)

    /// Warm secondary for food surfaces (chips, soft fills) without cream-page aesthetics.
    static let appAccentWarm = Color(red: 176/255, green: 122/255, blue: 74/255)

    static let appDanger = Color.red
    static let appWarning = Color.orange
    static let appSuccess = Color.green
    static let appOnAccent = Color.white

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

    static var groupedBackgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.windowBackgroundColor)
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

    static var elevatedSurfaceColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.textBackgroundColor)
        #else
        return Color.white
        #endif
    }
}

enum AppRadius {
    /// Controls / fields — tighter on Mac for AppKit density.
    static var control: CGFloat {
        #if os(macOS)
        8
        #else
        12
        #endif
    }

    static var panel: CGFloat {
        #if os(macOS)
        10
        #else
        14
        #endif
    }

    static var tile: CGFloat {
        #if os(macOS)
        12
        #else
        16
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

enum AppMotion {
    static let standardDuration: Double = 0.25
    static let bannerSpringResponse: Double = 0.35
    static let bannerSpringDamping: Double = 0.86

    static var standard: Animation { .easeInOut(duration: standardDuration) }
    static var banner: Animation {
        .spring(response: bannerSpringResponse, dampingFraction: bannerSpringDamping)
    }
}

extension View {
    @ViewBuilder
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        #if os(Android)
        self.animation(animation, value: value)
        #else
        self.modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
        #endif
    }
}

#if !os(Android)
private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
#endif

/// Semantic text styles (Dynamic Type). No custom font files required for Skip.
enum AppFont {
    static func largeTitle() -> Font { .largeTitle.weight(.bold) }
    static func title() -> Font { .title.weight(.bold) }
    static func title2() -> Font { .title2.weight(.semibold) }
    static func subtitle() -> Font { .body }
    static func headline() -> Font { .headline }
    static func subheadline() -> Font { .subheadline }
    static func body() -> Font { .body }
    static func callout() -> Font { .callout }
    static func footnote() -> Font { .footnote.weight(.medium) }
    static func caption() -> Font { .caption }
    static func caption2() -> Font { .caption2 }
    static func button() -> Font { .subheadline.weight(.semibold) }
    static func iconLarge() -> Font { .title.weight(.semibold) }
}

// MARK: - Reusable Components

struct CardContainer<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content
    let padding: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color?
    let borderColor: Color?
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
        let effectiveShadowColor = colorScheme == .dark ? shadowColor.opacity(0.22) : shadowColor

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
                    AppImage(name: systemImageName)
                }
                Text(title)
                    .font(AppFont.button())
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, fillWidth ? AppSpacing.lg : AppSpacing.md)
            .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
            .background(Color.appColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            #if os(macOS)
            .shadow(color: .clear, radius: 0)
            #else
            .shadow(
                color: Color.appColor.opacity(colorScheme == .dark ? 0.18 : 0.28),
                radius: 10,
                x: 0,
                y: 4
            )
            #endif
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
                    AppImage(name: systemImageName)
                }
                Text(title)
                    .font(AppFont.button())
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
            .background(Color.appColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var fillWidth: Bool = false
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.button())
                .foregroundStyle(Color.appColor)
                .padding(.vertical, 12)
                .padding(.horizontal, fillWidth ? AppSpacing.lg : AppSpacing.md)
                .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
                .background(Color.appColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
    }
}

struct DestructiveButton: View {
    let title: String
    var fillWidth: Bool = false
    var action: @MainActor () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(AppFont.button())
                .foregroundStyle(Color.white)
                .padding(.vertical, 12)
                .padding(.horizontal, fillWidth ? AppSpacing.lg : AppSpacing.md)
                .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
                .background(Color.red.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: fillWidth ? .infinity : nil, alignment: .center)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.red)
                .frame(width: 3)
            Text(message)
                .font(AppFont.footnote())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityLabel(message)
    }
}

struct EmptyState: View {
    let title: String
    var subtitle: String = ""
    var systemImage: String? = nil
    var actionTitle: String? = nil
    var action: (@MainActor () -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if let systemImage {
                ZStack {
                    Circle()
                        .fill(Color.appColor.opacity(0.12))
                        .frame(width: 72, height: 72)
                    AppImage(name: systemImage)
                        .font(AppFont.iconLarge())
                        .foregroundStyle(Color.appColor)
                }
            }
            Text(title)
                .font(AppFont.headline())
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                SecondaryButton(title: actionTitle, fillWidth: false, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }
}

struct LoadingBlock: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .accessibilityLabel("Loading")
    }
}

// MARK: - Text Inputs

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = nil

    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let leadingSystemImage {
                AppImage(name: leadingSystemImage)
                    .foregroundStyle(.secondary)
            }

            TextField(placeholder, text: $text)
                .font(AppFont.subtitle())
                .autocorrectionDisabled(true)
                .foregroundStyle(.primary)

            if let trailingSystemImage {
                AppImage(name: trailingSystemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 12)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.separatorColor.opacity(0.45), lineWidth: 1)
        )
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

#if os(Android)
    let secureIconOn = "visibility"
    let secureIconOff = "visibility_off"
#else
    let secureIconOn = "eye"
    let secureIconOff = "eye.slash"
#endif

    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let leadingSystemImage {
                AppImage(name: leadingSystemImage)
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
                    AppImage(name: isRevealed ? secureIconOff : secureIconOn)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if let trailingSystemImage {
                AppImage(name: trailingSystemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 12)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.separatorColor.opacity(0.45), lineWidth: 1)
        )
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
