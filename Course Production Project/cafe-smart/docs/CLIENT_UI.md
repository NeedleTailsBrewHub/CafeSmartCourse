# CafeSmart client UI notes

Design-system rules for Mac + Skip iOS/Android.

## Icons

- Use `AppImage(name:)` everywhere (SF Symbol on Apple, module asset on Android).
- Never put hand-rolled SVGs in `.symbolset` (Xcode requires SF Symbols template glyphs).
- Prefer `.imageset` for custom bitmaps (e.g. `lock.fill.imageset`) or existing `android_*` / `orders` / `visibility` assets.
- Android cart shortcut uses `orders`, not SF `cart.fill`.

## Typography

- `AppFont` maps to semantic `Font.TextStyle` (Dynamic Type). No Roboto bundle required.
- Do not set a global `.environment(\.font, .custom(...))`.

## Shared components (VenueSmartKit → `VenueSmartCore/DesignSystem/UITheme.swift`)

- Buttons: `PrimaryButton`, `SecondaryButton`, `DestructiveButton`
- Feedback: `ErrorBanner`, `EmptyState`, `LoadingBlock`
- Inputs: `AppTextField`, `AppSecureField` (Android reveal: `visibility` / `visibility_off`)

## Screen chrome (VenueSmartKit → `VenueSmartCore/DesignSystem/ScreenChrome.swift`)

- `ScreenCanvas` — scroll + `backgroundColor` + leading stack + `AppSpacing.lg`
- `SurfacePanel` / `PanelSection` — flat admin-style panels (no heavy shadows)
- `StatusChip`, `MetaLabel`, `StepperChips` — shared badges / steppers
- `AdaptiveDetailRow` — side-by-side on Mac/iPad regular; stacked on compact phone + Android

## Platform UI

- Phone home: circle `GridMenu`
- Mac home: dense dashboard rows + sidebar (not giant circles)
- Sheets: `ScrollView` + `VStack` (avoid `Form` on Android)

## AppIcon

- `Darwin/Assets.xcassets/AppIcon.appiconset` is trimmed to iPhone / iPad / Mac (+ marketing). No watchOS slots.
- If Xcode still reports unassigned children, delete leftover watch-sized PNGs from that folder (they are no longer referenced).
