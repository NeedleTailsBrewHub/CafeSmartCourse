//
//  ScreenChrome.swift
//  CafeSmartDev
//
//  Shared screen/list chrome — native Mac density + Skip phone/Android food-ordering patterns.
//

import SwiftUI

struct SectionHeader: View {
    var title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.headline())
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Scrollable screen shell: background + leading stack + consistent padding.
struct ScreenCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.lg)
        }
        .background(Color.groupedBackgroundColor)
    }
}

/// Flat surface panel. Soft border, minimal shadow so lists feel unified.
struct SurfacePanel<Content: View>: View {
    var padding: CGFloat = AppSpacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        CardContainer(
            padding: padding,
            cornerRadius: AppRadius.panel,
            backgroundColor: .surfaceColor,
            borderColor: .separatorColor.opacity(0.35),
            borderWidth: 1,
            shadowEnabled: false
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum StatusChipTone {
    case accent, warning, danger, success, neutral

    var foreground: Color {
        switch self {
        case .accent: return Color.appColor
        case .neutral: return Color.secondary
        case .warning: return Color.appWarning
        case .danger: return Color.appDanger
        case .success: return Color.appSuccess
        }
    }

    var background: Color { foreground.opacity(0.14) }
}

struct StatusChip: View {
    let text: String
    var tone: StatusChipTone = .accent
    var selected: Bool = false

    var body: some View {
        Text(text)
            .font(AppFont.footnote())
            .foregroundStyle(selected ? Color.white : tone.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.appColor : tone.background)
            .clipShape(Capsule())
            .accessibilityLabel(text)
            .accessibilityValue(selected ? "Selected" : "")
    }
}

struct MetaLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            AppImage(name: icon)
            Text(text)
        }
        .font(AppFont.footnote())
        .foregroundStyle(.secondary)
    }
}

/// Content + actions: side-by-side on Mac / regular width; stacked on compact phone/Android.
struct AdaptiveDetailRow<Content: View, Actions: View>: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
#endif
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    private var stackVertically: Bool {
#if os(macOS)
        false
#elseif os(Android)
        true
#elseif os(iOS)
        sizeClass == .compact
#else
        true
#endif
    }

    var body: some View {
        if stackVertically {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                content()
                actions()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                content()
                Spacer(minLength: AppSpacing.sm)
                actions()
            }
        }
    }
}

struct StepperChips: View {
    let minusIcon: String
    let plusIcon: String
    var valueLabel: String? = nil
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button(action: onMinus) {
                IconChip(name: minusIcon)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Decrease quantity")
            if let valueLabel {
                Text(valueLabel)
                    .font(AppFont.body())
                    .frame(minWidth: 28)
                    .monospacedDigit()
                    .accessibilityLabel("Quantity \(valueLabel)")
            }
            Button(action: onPlus) {
                IconChip(name: plusIcon)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Increase quantity")
        }
    }
}

/// Section header + flat panel — Matches Models admin grouping on every platform.
struct PanelSection<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(title: title, subtitle: subtitle)
            SurfacePanel {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Food-ordering building blocks

struct BrandAvatar: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Logo", bundle: .module)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.appColor.opacity(0.22), lineWidth: 1))
            .accessibilityLabel("CafeSmart")
    }
}

struct WelcomeHeader: View {
    let name: String
    var subtitle: String = "Ready to order?"
    var showAvatarLink: Bool = false
    var onAvatar: (@MainActor () -> Void)? = nil

    init(
        name: String,
        subtitle: String = "Ready to order?",
        showAvatarLink: Bool = false,
        onAvatar: (@MainActor () -> Void)? = nil
    ) {
        self.name = name
        self.subtitle = subtitle
        self.showAvatarLink = showAvatarLink
        self.onAvatar = onAvatar
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(AppFont.footnote())
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(AppFont.title2())
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AppSpacing.sm)
            if showAvatarLink, let onAvatar {
                Button(action: onAvatar) {
                    BrandAvatar(size: 48)
                }
                .buttonStyle(.plain)
            } else {
                BrandAvatar(size: 48)
            }
        }
    }
}

/// Primary ordering CTA — the heart of the café app on phone/Android.
struct OrderHeroCard: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let iconName: String
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 52, height: 52)
                    AppImage(name: iconName)
                        .font(AppFont.title2())
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.headline())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(AppFont.caption())
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(actionTitle)
                    .font(AppFont.button())
                    .foregroundStyle(Color.appColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            }
            .padding(AppSpacing.md)
            .background(
                LinearGradient(
                    colors: [Color.appColor, Color.appColor.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(actionTitle)")
    }
}

/// Compact navigation row — replaces giant circle grids on phone.
struct QuickActionRow: View {
    let title: String
    let subtitle: String
    let systemName: String
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(Color.appColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    AppImage(name: systemName)
                        .foregroundStyle(Color.appColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.headline())
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
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
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct QuickActionList: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemName: String
        let route: HomeRoute
    }

    var items: [Item]
    var onTap: @MainActor (Item) -> Void

    var body: some View {
        SurfacePanel(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    QuickActionRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        systemName: item.systemName
                    ) {
                        onTap(item)
                    }
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
        }
    }
}

/// Leading glyph tile for menu rows (no remote food photos required).
struct MenuGlyph: View {
    let category: String?
    var size: CGFloat = 52

#if os(Android)
    private var iconName: String { "android_coffee_cup" }
#else
    private var iconName: String {
        let key = (category ?? "").lowercased()
        if key.contains("tea") { return "cup.and.saucer.fill" }
        if key.contains("pastry") || key.contains("bakery") || key.contains("food") {
            return "fork.knife"
        }
        if key.contains("cold") || key.contains("smoothie") { return "snowflake" }
        return "cup.and.saucer.fill"
    }
#endif

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.appColor.opacity(0.18),
                            Color.appAccentWarm.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            AppImage(name: iconName)
                .font(AppFont.title2())
                .foregroundStyle(Color.appColor)
        }
        .accessibilityHidden(true)
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    var showsAdd: Bool = false
    var addTitle: String = "Add"
    var onAdd: (@MainActor () -> Void)? = nil

    init(
        item: MenuItem,
        showsAdd: Bool = false,
        addTitle: String = "Add",
        onAdd: (@MainActor () -> Void)? = nil
    ) {
        self.item = item
        self.showsAdd = showsAdd
        self.addTitle = addTitle
        self.onAdd = onAdd
    }

    var body: some View {
        MenuOrderRow(item: item, showsAdd: showsAdd, onAdd: onAdd)
    }
}

/// Dense consumer menu row — glyph, copy, price, and a compact circular add control.
struct MenuOrderRow: View {
    let item: MenuItem
    var showsAdd: Bool = false
    var onAdd: (@MainActor () -> Void)? = nil

#if os(Android)
    private var plusIcon: String { "android_plus" }
#else
    private var plusIcon: String { "plus" }
#endif

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            MenuGlyph(category: item.category, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AppFont.headline())
                    .foregroundStyle(.primary)
                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(AppFont.footnote())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(CurrencyHelper.format(cents: item.priceCents))
                        .font(AppFont.callout())
                        .foregroundStyle(Color.appColor)
                    if let prep = item.prepSeconds, prep > 0 {
                        Text("· \(max(1, prep / 60)) min")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if let allergens = item.allergens, !allergens.isEmpty {
                    Text(allergens.map(\.rawValue).joined(separator: " · "))
                        .font(AppFont.caption2())
                        .foregroundStyle(Color.appWarning)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if showsAdd, let onAdd {
                Button(action: onAdd) {
                    ZStack {
                        Circle()
                            .fill(Color.appColor)
                            .frame(width: 36, height: 36)
                        AppImage(name: plusIcon)
                            .font(AppFont.headline())
                            .foregroundStyle(Color.appOnAccent)
                    }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(
                    (item.sizeOptions?.isEmpty == false) ? "Customize \(item.name)" : "Add \(item.name)"
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, AppSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [item.name, CurrencyHelper.format(cents: item.priceCents)]
        if let prep = item.prepSeconds, prep > 0 {
            parts.append("about \(max(1, prep / 60)) minutes")
        }
        if let allergens = item.allergens, !allergens.isEmpty {
            parts.append("allergens \(allergens.map(\.rawValue).joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
    }
}

struct FeaturedMenuCard: View {
    let item: MenuItem
    var onTap: @MainActor () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                MenuGlyph(category: item.category, size: 72)
                Text(item.name)
                    .font(AppFont.headline())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(CurrencyHelper.format(cents: item.priceCents))
                    .font(AppFont.callout())
                    .foregroundStyle(Color.appColor)
            }
            .padding(AppSpacing.md)
            .frame(width: 148, alignment: .leading)
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                    .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(CurrencyHelper.format(cents: item.priceCents))")
    }
}

struct IconChip: View {
    var name: String
    var body: some View {
        AppImage(name: name)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(AppSpacing.xs + 2)
            .frame(width: 32, height: 32)
            .foregroundStyle(Color.appColor)
            .background(Color.appColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}

struct CategoryChipBar: View {
    let categories: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selection = nil
                } label: {
                    StatusChip(text: "All", tone: .accent, selected: selection == nil)
                }
                .buttonStyle(.plain)

                ForEach(categories, id: \.self) { category in
                    Button {
                        selection = category
                    } label: {
                        StatusChip(
                            text: category,
                            tone: .neutral,
                            selected: selection == category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#if os(macOS)
/// Dense Mac dashboard metric — AppKit-style summary tile.
struct MetricTile: View {
    let title: String
    let value: String
    let systemName: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.appColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: systemName)
                    .foregroundStyle(Color.appColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppFont.headline())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
        )
    }
}
#endif
