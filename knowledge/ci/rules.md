# CI rules

- Keep marketing version in `VERSION`; `build.sh` stamps Info.plist from it.
- Tag releases as `v` + semver (`v1.1.0`) matching `VERSION`.
- Build on macOS runners only (`macos-14`+); do not attempt Linux SwiftUI app builds.
- Publish a zip that contains `LookAway.app` at the top level so users can drag it into Applications.
