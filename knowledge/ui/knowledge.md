# Liquid Glass — Look Away

## Pattern (Apple SwiftUI)

Follow [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views):

- **Menu panel:** one outer `.glassEffect(.regular.tint(...), in: .rect(cornerRadius:))` via `LookAwayGlassPanel`. **No** `GlassEffectContainer` wrapper around the whole panel. **No** extra `clipShape` on the liquid-glass path (mismatched continuous vs circular corners caused a double-border artifact).
- **Window chrome:** MenuBarExtra `.window` background must be cleared via `MenuBarWindowBackgroundClearer` (AppKit: clear window + hide injected `NSVisualEffectView`) so the system rounded rect does not peek behind the glass panel.
- **Inner controls:** `lookAwayControlSurface` / `lookAwayCapsuleSurface` — subtle pink-tinted fills, not nested glass.
- **Break overlay timer:** direct `.glassEffect` on the bold countdown pill only.
- Apply `.glassEffect` **after** padding and overlays that affect appearance.

## Palette

- Single accent: `LookAwayBrand.accent` — `Color(red: 1.0, green: 0.42, blue: 0.78)`
- Soft tint: `LookAwayBrand.accentSoft` — for highlights
- Glass tints: `LookAwayGlass.menuPanelTint`, `LookAwayGlass.overlayTint` (pink at low opacity)
- Destructive: system red only (skip penalty, quit)

## Do not use

- AppKit `NSGlassEffectView` via KVC/`NSViewRepresentable` — unstable from SwiftUI hosting views.
- Nested glass plates under labels inside an already-glass panel — blurs text and shows border artifacts.
- Extra `clipShape(RoundedRectangle(..., style: .continuous))` on top of `glassEffect(..., in: .rect(cornerRadius:))` — different corner curves → double border at corners.
- Multiple accent colors (forest, wood, sage, etc.) — removed intentionally.
- In-app Settings panel — removed; use `config.json` + first-launch login prompt.

## Build

`./build.sh` probes the SDK for `glassEffect` and defines `LIQUID_GLASS` when available (macOS 26 SDK). Without it, the app uses `.ultraThinMaterial` and subtle fill fallbacks.

## Files

- `LookAway/Views/GlassStyles.swift` — `LookAwayGlassPanel`, tokens, button backgrounds
- `LookAway/Views/LookAwayDesign.swift` — accent colors, metrics, status chips
- `LookAway/Services/MenuBarWindowBackground.swift` — clear MenuBarExtra window chrome
