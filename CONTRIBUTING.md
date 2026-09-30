# Contributing to Look Away

Thank you for considering a contribution. This project is a native macOS menu bar app built with Swift and SwiftUI.

## Before you start

1. Read the [README](README.md) for build instructions and architecture overview.
2. Skim [`knowledge/INDEX.md`](knowledge/INDEX.md) for UI and overlay conventions.
3. Search [existing issues](https://github.com/zj05409/look-away/issues) to avoid duplicate work.
4. For large changes, open an issue first to discuss the approach.

## Development setup

### Requirements

- macOS 14 (Sonoma) or later
- Apple Command Line Tools (`xcode-select --install`)
- Xcode 15+ (optional, for the Xcode project workflow)
- Xcode 26 / macOS 26 SDK (optional, for native Liquid Glass at compile time)

### Quick build

```bash
./build.sh
open build/LookAway.app
```

The script prints whether **Liquid Glass** is enabled (`LIQUID_GLASS` compile flag) or material fallbacks are used. It also writes `build/LookAway-<version>-<sha>.zip`.

### Xcode workflow

1. Open `LookAway.xcodeproj`.
2. Select the LookAway target → Signing & Capabilities → choose your development team.
3. (Optional) Add `LIQUID_GLASS` to **Active Compilation Conditions** when using the macOS 26 SDK.
4. Build and run (`Cmd+R`).

## Project structure

| Path | Purpose |
|------|---------|
| `LookAway/LookAwayApp.swift` | App entry point, menu bar extra |
| `LookAway/Models/` | Data models (`AppConfig`, `BreakStats`, `BreakSession`) and `L10n` strings |
| `LookAway/Services/` | Timer, config, monitors (mic, sleep), launch-at-login, input shield |
| `LookAway/Views/` | SwiftUI UI — menu panel, break overlay, glass styles, controls |
| `LookAway/Controllers/` | `NSPanel` overlay controller for multi-display breaks |
| `knowledge/` | Internal design notes (liquid glass, break overlay, palette) |
| `scripts/` | App icon generation |
| `build.sh` | Command-line build without full Xcode |
| `VERSION` | Marketing semver for CI and `CFBundleShortVersionString` |
| `.github/workflows/build.yml` | macOS CI — artifact + Releases |

### Key files

| File | Purpose |
|------|---------|
| `TimerEngine.swift` | Work/break/pause phases, skip penalty |
| `BreakOverlayController.swift` | Multi-monitor black overlay panels |
| `BreakOverlayView.swift` | Lock screen UI — glass timer, title, skip |
| `BreakInputShield.swift` | Blocks ⌘Q / ⌘W / ⌘Tab / Esc during breaks |
| `GlassStyles.swift` | `LookAwayGlassPanel`, liquid glass helpers, button styles |
| `LookAwayDesign.swift` | Pink accent tokens, layout metrics, status chips |
| `MenuBarView.swift` | Menu bar panel |
| `MenuControls.swift` | Hold-to-confirm buttons |
| `MenuBarWindowBackground.swift` | Clears MenuBarExtra chrome (prevents double border) |
| `BreakStats.swift` | Pending skip penalty (`stats.json`) and in-progress break (`session.json`) persistence |
| `L10n.swift` | Chinese / English UI text; wrap new user-facing strings in `L10n.text(english, chinese)` |
| `LaunchAtLoginManager.swift` | First-launch prompt + login item registration |
| `MenuBarWindowDismisser.swift` | Closes menu bar window when break starts |

## UI guidelines

- **One accent color** — `LookAwayBrand.accent` (pink). Do not introduce secondary earthy or multi-accent palettes.
- **Menu panel** — single outer `glassEffect` via `LookAwayGlassPanel` on a **clear** MenuBarExtra window. Do not add a second clipShape with a different corner style. Inner controls use `lookAwayControlSurface` fills, not nested glass.
- **Break overlay** — true black background. Glass only on the countdown timer. No full-screen containers or photo backgrounds.
- **Liquid Glass** — follow [Apple’s SwiftUI guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Do not use AppKit `NSGlassEffectView` KVC bridges from SwiftUI.
- Apply `.glassEffect` **after** padding and overlays that affect layout.
- No in-app Settings panel — intervals and advanced options live in `config.json`.

## Coding guidelines

- Match existing Swift style: `@MainActor` for UI-bound services, `ObservableObject` + `@Published` for state.
- Keep menu bar updates lightweight — `TimerEngine` publishes display fields only when values change.
- Prefer extending existing services over adding parallel implementations.
- No new dependencies unless discussed in an issue first; the app intentionally stays dependency-free.
- Test on both Apple Silicon and Intel when touching build or platform code.
- When changing `build.sh` source list, update `LookAway.xcodeproj` in the same PR.
- Bump [`VERSION`](VERSION) when cutting a user-facing release; tag as `vX.Y.Z`.

## Pull request process

1. Fork the repository and create a branch from `main`.
2. Make focused changes with a clear commit message.
3. Verify the app builds with `./build.sh` (or Xcode).
4. Manually smoke-test:
   - Timer tick, pause/resume, restart (hold)
   - Break overlay: black screen, bold glass timer, **Look Away** title, faint skip
   - Hold **Skip** on overlay or menu ends break early (penalty applied)
   - Menu bar closes and disables during break
   - Menu panel corners look uniform (no double-radius / system chrome peeking)
   - First-launch launch-at-login prompt (reset `defaults delete io.github.zj05409.lookaway lookAway.hasPromptedLaunchAtLogin` to retest)
   - `config.json` edits reload while running (including `language`)
   - Quit/kill the app during a break (`killall LookAway`) and relaunch: the break resumes
5. Open a PR describing **what** changed and **why**.
6. Link any related issues.

## Reporting bugs

Include:

- macOS version and chip (Apple Silicon / Intel)
- How you built the app (`build.sh` vs Xcode vs downloaded release) and whether Liquid Glass was enabled in the build log
- Steps to reproduce
- Expected vs actual behavior
- Screenshots or screen recordings when UI-related
- Single vs multi-monitor setup if overlay-related

## Feature requests

Open an issue with:

- The problem you want solved
- Proposed behavior
- Why it fits the scope of a focused break-timer menu bar app

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
