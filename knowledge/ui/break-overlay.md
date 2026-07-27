# Break overlay (lock screen)

## Layout (top → bottom, centered)

1. **Countdown** — bold monospaced timer in a pink-tinted liquid glass pill
2. **Look Away** — title below the timer
3. **Skip** — hold-to-skip at bottom of screen (~20% opacity)

## Background

- True black (`Color.black`) on every display via opaque `NSPanel`
- No photos, gradients, or earthy/nature imagery

## Skip friction

- Hold **11 seconds** on overlay skip or menu bar **Skip** / **Restart** during break
- Adds `skipPenaltyMinutes` to next break

## Files

- `LookAway/Views/BreakOverlayView.swift` — overlay SwiftUI
- `LookAway/Controllers/BreakOverlayController.swift` — multi-monitor panels + input shield
