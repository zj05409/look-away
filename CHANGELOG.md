# Changelog

Release notes for tagged versions. CI copies the section matching `VERSION` into the GitHub Release.

## 1.3.0

- **Breaks survive quitting or killing the app** — an in-progress break (or one waiting for "Start Working") is saved to `~/.config/look-away/session.json`; relaunching restores the overlay with the remaining time.
- **Fix:** editing `config.json` during a break no longer drops the skip-penalty minutes from that break.
- **Chinese / English UI** — new `language` key in `config.json` (`zh` default, `en`, or `auto` to follow macOS). All menu, overlay, notification, and first-launch text is now consistent.
- **Universal app** — release builds now run natively on both Apple Silicon and Intel Macs.
- **Fix:** the Xcode project was missing `BreakCompletionEventWriter.swift` and used the upstream bundle id.
- Docs point at this fork; added an iPhone / Android feasibility note (`knowledge/mobile/feasibility.md`).

## 1.2.2

- Write a local `break-complete` event (`~/.config/look-away/break-complete.json`) when a required break ends.

## 1.2.1

- Timers keep running on wall-clock time while the screen is locked, the display is off, or the Mac sleeps.

## 1.2.0

- Fork-branded build (`io.github.zj05409.lookaway`), explicit "Start Working" after breaks, configurable reminder text, in-app pre-break countdown.
