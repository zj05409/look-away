# iPhone & Android feasibility

Can Look Away's core idea (a repeating work timer that **forces** a break by covering the screen) run on phones? Short answer: **Android — yes, almost fully. iPhone — partially, through Apple's Screen Time APIs, not with a true full-screen overlay.**

## What the macOS app relies on

| macOS capability | Used for |
|------------------|----------|
| Always-running menu bar process | Countdown timer |
| Shielding-level `NSPanel` on every display | Unskippable black overlay |
| Event monitors | Blocking ⌘Q / ⌘Tab / Esc during a break |
| CoreAudio "device running" | Deferring breaks during calls |
| Files in `~/.config/look-away/` | Config, penalty, session, `break-complete` event |

## Android

| Need | Android API | Notes |
|------|-------------|-------|
| Timer that survives backgrounding | Foreground service (`specialUse` / `shortService` type) + `AlarmManager.setExactAndAllowWhileIdle` | Persistent notification shows the countdown |
| Full-screen break overlay | `SYSTEM_ALERT_WINDOW` ("Display over other apps") with `TYPE_APPLICATION_OVERLAY` | User grants once in Settings; covers everything except system UI shades |
| Stronger lock | `DevicePolicyManager.lockNow()` (Device Admin) or Accessibility service that sends the user back to the overlay | Accessibility use must be justified on Google Play; fine for sideloaded APKs |
| Count only real screen time | `ACTION_SCREEN_ON/OFF`, `ACTION_USER_PRESENT`, `UsageStatsManager` | Matches the Mac's wall-clock policy or an "active use" policy |
| Skip during calls | `TelephonyManager` call state, `AudioManager.mode == MODE_IN_COMMUNICATION` | Covers phone and VoIP calls |
| Hold-to-skip + penalty | Plain Compose UI + DataStore | Same rules as `TimerEngine` |

Status: **implemented** in [`android/`](../../android/) (v1.4.0) — foreground service + overlay, screen-time counting, call deferral, persisted state.

Verdict: feature parity is realistic. Kotlin + Jetpack Compose, one foreground service, one overlay view. APKs can be built on the existing GitHub Actions (Ubuntu runner) and sideloaded without a store account.

## iPhone (iOS)

iOS does **not** allow an app to draw over other apps or keep a timer running indefinitely in the background. The supported path is the **Screen Time API** (iOS 16+ for self-use):

| Need | iOS API | Limits |
|------|---------|--------|
| Schedule work/break cycles | `DeviceActivity` (`DeviceActivitySchedule`, `DeviceActivityEvent` usage thresholds) + a `DeviceActivityMonitor` extension | Minimum schedule interval is 15 minutes; thresholds count **usage**, not wall-clock time |
| Block the phone during a break | `ManagedSettings` shields on all apps/categories (`FamilyControls` individual authorization) | Phone, Messages, and Settings stay reachable; shield UI is customizable (icon, title, text, buttons) via `ShieldConfiguration` extension but cannot show a live countdown |
| Visible countdown | Live Activity / Dynamic Island (`ActivityKit`) + local notifications | Countdown with `Text(timerInterval:)` updates without the app running |
| Skip during calls | Not available to third-party apps in the background | Can be approximated with a manual "In a call" button |

Requirements and caveats:

- Needs Xcode, an Apple Developer account ($99/yr) and the **Family Controls** entitlement; development builds work, App Store / TestFlight distribution needs Apple's approval of the entitlement.
- Free Apple IDs can sideload for 7 days only.
- Users can always revoke Screen Time authorization in Settings — enforcement is "friction", not a hard lock (same spirit as the Mac hold-to-skip).

Verdict: a useful iPhone companion is feasible (usage-based breaks that shield all apps + Live Activity countdown), but it will not look or behave exactly like the Mac overlay.

## Connecting phone and Mac

The most valuable phone feature is often **not letting the phone replace the screen during a Mac break**. Options, from least to most work:

1. **Notification bridge (no app)** — the Mac already writes `~/.config/look-away/break-complete.json`. A local script (or a future `webhookURL` config) can POST to a push service: [Bark](https://github.com/Finb/Bark) (iOS), [ntfy](https://ntfy.sh) (Android + iOS). Adding a matching `break-start` event would let the phone announce the break too.
2. **Android companion subscribed to ntfy** — on `break-start`, the Android app shows its overlay for the same duration; on `break-complete`, it dismisses.
3. **iOS companion** — can react to a push only by notifying the user; shields should come from its own on-device `DeviceActivity` schedule aligned with the Mac's `workDurationMinutes` / `breakDurationMinutes`.

## Suggested order

1. Add `break-start` events (and optionally a webhook) on the Mac — small, immediately useful for both phones.
2. Android app (Kotlin/Compose, overlay + foreground service), built by CI.
3. iOS companion (Screen Time shields + Live Activity) once a developer account and entitlement are available.
