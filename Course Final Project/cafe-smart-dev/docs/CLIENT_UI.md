# CafeSmartDev client UI notes

Design-system rules for Mac + Skip iOS/Android (premium café ordering / ops).

## Icons

- Use `AppImage(name:)` everywhere (SF Symbol on Apple, module asset on Android).
- Never put hand-rolled SVGs in `.symbolset`.
- Prefer `.imageset` for custom bitmaps (e.g. `lock.fill.imageset`) or existing `android_*` / `orders` / `visibility` assets.
- Android cart shortcut uses `orders`, not SF `cart.fill`.

## Typography

- `AppFont` maps to semantic `Font.TextStyle` (Dynamic Type).

## Brand / chrome

- Accent: `Color.appColor` (café teal). Warm secondary: `Color.appAccentWarm`.
- Status: `appDanger`, `appWarning`, `appSuccess`, `appOnAccent`.
- Backgrounds: `groupedBackgroundColor` for screens, `surfaceColor` for panels.
- Radii: `AppRadius.control` / `.panel` / `.tile` (tighter on Mac).
- Motion: `AppMotion.standard` / `.banner` via `.appAnimation` (honors Reduce Motion on Apple).

## Shared components (`DesignSystem/`)

- Buttons: `PrimaryButton`, `SecondaryButton`, `DestructiveButton`
- Feedback: `ErrorBanner`, `EmptyState`, `LoadingBlock`
- Inputs: `AppTextField`, `AppSecureField` (leading icons inside the field)
- Chrome: `ScreenCanvas`, `SurfacePanel`, `PanelSection`, `SectionHeader`, `IconChip`
- Food UI: `WelcomeHeader`, `OrderHeroCard`, `QuickActionList`, `MenuGlyph`, `MenuItemRow`, `CategoryChipBar`, `BrandAvatar`
- Mac-only: `MetricTile`

## Platform UI

- Phone / Android: `TabView` (Home · Order · Orders · Profile) with cart/order badges
- Order flow: search, category chips, grouped sections, sticky cart bar, review sheet
- Cart: app-level `CartViewModel` with local persistence
- Mac: `NavigationSplitView` + min window 980×680, unified toolbar, split order (menu | cart)
- Sheets: `ScrollView` + `VStack` (avoid `Form` on Android); size choices use chips, not Pickers
- Auth / onboarding: content max-width ~480–520pt on wide displays

## Accessibility

- Steppers announce increase/decrease + quantity
- Category chips expose selected state
- Menu rows combine name, price, prep, allergens into one label
- Prefer text + color for status (never color alone)
