# Look Away

A native macOS menu bar app that reminds you to step away from the screen on a repeating timer. When a work interval ends, a full-screen black break overlay covers all displays until the break finishes—or you end it early with deliberate friction.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build](https://github.com/dvdcarlomagno/look-away/actions/workflows/build.yml/badge.svg)](https://github.com/dvdcarlomagno/look-away/actions/workflows/build.yml)

## Download (no build required)

Every commit to `main` publishes a macOS app zip on the **[Latest release](https://github.com/dvdcarlomagno/look-away/releases/latest)**.

1. Download **[LookAway.app.zip](https://github.com/dvdcarlomagno/look-away/releases/latest/download/LookAway.app.zip)**
2. Unzip
3. Drag `LookAway.app` into **Applications**
4. First open: right-click → **Open** if macOS Gatekeeper blocks the unsigned build

Versioned releases (tags like `v1.1.0`) keep older builds under [Releases](https://github.com/dvdcarlomagno/look-away/releases). CI also attaches the zip to each [Actions run](https://github.com/dvdcarlomagno/look-away/actions/workflows/build.yml).

## Features

- Menu bar countdown timer with phase icon
- **Skip penalty** — ending a break early adds extra minutes to your next break (configurable)
- Work and break durations via `~/.config/look-away/config.json` (live reload while the app is running)
- Full-screen **black break overlay** on all monitors — minimal UI, keyboard focus captured
- Break overlay hardening — shielding window level, blocked shortcuts (⌘Q, ⌘W, ⌘Tab, Esc), menu bar disabled during breaks
- Skips breaks while the microphone is in use (calls/meetings) — checks **all** input devices, not just the system default
- Pauses while the display is off, the Mac is asleep, or the screen is locked; **resumes** where you left off on a short return, **restarts the work timer** when away time reaches the configured break duration (manual pause always resumes)
- **Launch at login** — prompted on first launch (default: enable); change later in System Settings → General → Login Items, or set `launchAtLogin` in `config.json`
- Pre-break warning notification (optional, off by default) with **Extend 3 minutes** action in the notification and menu bar
- Native Liquid Glass UI on macOS 26 via SwiftUI `glassEffect` (material fallback on older macOS / SDKs)

## Design

- **Single accent color** — warm pink (`LookAwayBrand.accent`) used across the menu panel and break overlay glass tints
- **Menu panel** — one outer liquid-glass shell over a clear MenuBarExtra window (avoids double-corner artifacts); inner buttons use subtle fills (no nested glass)
- **Break overlay** — true black background, no photo backgrounds or earthy palette

## Requirements

- macOS 14 (Sonoma) or later
- **Apple Command Line Tools** (no full Xcode required for `build.sh`)
- **macOS 26 SDK / Xcode 26** (optional) — enables native SwiftUI Liquid Glass at build time; otherwise the app uses material fallbacks

Install Command Line Tools if needed:

```bash
xcode-select --install
```

## Quick start

Clone the repository:

```bash
git clone git@github.com:dvdcarlomagno/look-away.git
cd look-away
```

Build and run:

```bash
./build.sh
open build/LookAway.app
```

This compiles with `swiftc`, wraps the binary in a `.app` bundle, generates the pink **eyes** app icon, ad-hoc signs it for local use, and writes `build/LookAway-<version>-<sha>.zip`. The build script probes the SDK and prints whether Liquid Glass is enabled.

If macOS blocks the first launch, right-click the app → **Open**.

## Versioning & CI

| Piece | Role |
|-------|------|
| [`VERSION`](VERSION) | Marketing semver (`CFBundleShortVersionString`), e.g. `1.1.0` |
| Git commit count | `CFBundleVersion` (monotonic build number) |
| Tag `v1.1.0` | Versioned GitHub Release with a downloadable zip |
| Push to `main` | Rebuilds and updates the rolling **Latest** release |

**Cut a versioned release**

1. Bump the `VERSION` file (and `CFBundleShortVersionString` in `LookAway/Info.plist` if you edit it by hand — `build.sh` overwrites it from `VERSION`).
2. Commit on `main`.
3. Tag and push:

```bash
git tag v1.1.0
git push origin v1.1.0
```

CI builds on the tag and publishes a GitHub Release with `LookAway.app.zip`.

## Build with Xcode (optional)

If you have Xcode installed:

1. Open `LookAway.xcodeproj` in Xcode.
2. Select the **LookAway** target → **Signing & Capabilities** → choose your development team.
3. Build and run (`Cmd+R`).

For Liquid Glass in Xcode, add `LIQUID_GLASS` to **Active Compilation Conditions** when building with the macOS 26 SDK (same flag `build.sh` sets automatically).

## First launch

On first launch the app:

1. Creates `~/.config/look-away/config.json` with defaults (if missing)
2. Asks whether to **Open at Login** (default button enables it)

```json
{
  "workDurationMinutes": 120,
  "breakDurationMinutes": 15,
  "preBreakWarningMinutes": 0,
  "skipPenaltyMinutes": 5,
  "launchAtLogin": true
}
```

Skip-penalty state is stored separately in `~/.config/look-away/stats.json`.

Copy values from [`config.example.json`](config.example.json) if you prefer to start from the repo template.

## Config reference

| Key | Default | Description |
|-----|---------|-------------|
| `workDurationMinutes` | `120` | Minutes before a break starts |
| `breakDurationMinutes` | `15` | Break overlay duration |
| `preBreakWarningMinutes` | `0` | Minutes before break to notify (`0` = off) |
| `skipPenaltyMinutes` | `5` | Extra minutes added to the next break after an early skip (`0` = off) |
| `launchAtLogin` | `true` | Register app at login (also set by the first-launch prompt) |

Edit the file while the app is running—it reloads automatically. After the first-launch prompt, changing `launchAtLogin` in the file updates the login item.

## Menu bar controls

- **Pause / Resume** — manual timer pause (single tap)
- **Extend 3 min** — shown during the pre-break warning; adds 3 minutes to the work session (also available as a notification action)
- **Restart** — hold **11 seconds** to reset the work timer; during a break, same hold ends the break early (penalty applies)
- **Break / Skip** — start a break, or hold **Skip** for **11 seconds** during a break to end early
- **Quit** — disabled while a break is active

The menu bar panel closes automatically when a break starts. The menu bar icon is dimmed and disabled during breaks.

## Break overlay

When a break starts, a full-screen **true black** overlay covers every connected display:

| Element | Description |
|---------|-------------|
| Countdown | **Bold** timer with pink-tinted liquid glass pill |
| Title | **Look Away** below the timer |
| Skip | Faint hold-to-skip control at the bottom (~20% opacity, hold **11 seconds**) |

You can also end a break early from the menu bar **Skip** control (hold 11 seconds).

The overlay uses a shielding window level, captures keyboard focus, and blocks common escape shortcuts.

## Architecture

```
LookAwayApp (MenuBarExtra)
    └── AppViewModel
            ├── ConfigManager           → ~/.config/look-away/config.json
            ├── TimerEngine             → work / break / pause phases & skip penalty
            ├── MicrophoneMonitor       → skip breaks during calls
            ├── SleepWakeMonitor        → pause while away; long return restarts work timer
            └── BreakOverlayController  → full-screen black NSPanel per display
                    └── BreakInputShield → keyboard shortcut blocking during breaks
```

| Component | Role |
|-----------|------|
| `TimerEngine` | Core countdown logic, phase transitions, skip penalty, menu bar label updates |
| `BreakOverlayController` | Multi-display panels, keep-front timer |
| `BreakOverlayView` | Black overlay UI — glass timer, title, skip |
| `BreakInputShield` | Local/global event monitors for blocked shortcuts during breaks |
| `BreakStats` / `stats.json` | Persists pending skip penalty |
| `GlassStyles` / `LookAwayDesign` | Pink accent tokens, `LookAwayGlassPanel`, liquid glass helpers |
| `ConfigManager` | JSON persistence with file watcher for live reload |
| `LaunchAtLoginManager` | First-launch prompt + `SMAppService` registration |

## App icon

`./build.sh` generates a pink gradient icon with a white **eyes** SF Symbol via `scripts/generate_app_icon.swift`, bundles it as `AppIcon.icns`, and sets `CFBundleIconFile`.

To regenerate only the icon assets:

```bash
swift scripts/generate_app_icon.swift LookAway/Resources/AppIcon.iconset
iconutil -c icns LookAway/Resources/AppIcon.iconset -o LookAway/Resources/AppIcon.icns
```

If Finder still shows the old icon after rebuilding, restart the Dock:

```bash
killall Dock
```

## Permissions

- **Microphone usage description** is included so macOS can detect when the mic is active during calls. The app does **not** record audio. Call detection scans every audio input device (built-in and external), so a break is deferred even when the active call uses a non-default microphone.
- **Accessibility** (optional) — granting Look Away Accessibility access in System Settings improves global shortcut blocking during breaks. Local blocking works when the app is frontmost without this permission.

## Skipping vs completing a break

| Action | Next break penalty |
|--------|-------------------|
| Complete break (timer reaches 0) | None |
| **Skip** on overlay (hold 11s) or menu **Skip** / **Restart** during break | +`skipPenaltyMinutes` |

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, project structure, and pull request guidelines.

Internal design notes live in [`knowledge/`](knowledge/INDEX.md).

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE).

## Acknowledgments

Inspired by the need for a simple, native macOS break timer that respects calls and sleep without cloud accounts or subscriptions.
