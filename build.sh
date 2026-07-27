#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LookAway"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
SDK="$(xcrun --show-sdk-path)"

# Version from VERSION file (semver) + git commit for CFBundleVersion
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
  GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
else
  BUILD_NUMBER="1"
  GIT_SHA="local"
fi

# Detect Apple Silicon vs Intel
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  TARGET="arm64-apple-macosx14.0"
else
  TARGET="x86_64-apple-macosx14.0"
fi

SWIFT_FLAGS=()
GLASS_PROBE="$(mktemp /tmp/lookaway_glass_probe.XXXXXX.swift)"
cat > "$GLASS_PROBE" <<'EOF'
import SwiftUI
@available(macOS 26, *)
func lookAwayGlassProbe() -> some View {
    Text("probe").glassEffect()
}
EOF
if swiftc -typecheck "$GLASS_PROBE" -sdk "$SDK" -target "$TARGET" 2>/dev/null; then
  SWIFT_FLAGS+=(-D LIQUID_GLASS)
  echo "Liquid Glass: enabled (SwiftUI glassEffect available in SDK)"
else
  echo "Liquid Glass: using material fallback (SDK lacks glassEffect)"
fi
rm -f "$GLASS_PROBE"

echo "Building $APP_NAME for $TARGET ..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

swiftc \
  -o "$MACOS_DIR/$APP_NAME" \
  -target "$TARGET" \
  -sdk "$SDK" \
  "${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework CoreAudio \
  -framework CoreGraphics \
  -framework UserNotifications \
  -framework ServiceManagement \
  "$ROOT/LookAway/LookAwayApp.swift" \
  "$ROOT/LookAway/Models/Config.swift" \
  "$ROOT/LookAway/Models/BreakStats.swift" \
  "$ROOT/LookAway/Services/ConfigManager.swift" \
  "$ROOT/LookAway/Services/TimerEngine.swift" \
  "$ROOT/LookAway/Services/NotificationHandler.swift" \
  "$ROOT/LookAway/Services/MicrophoneMonitor.swift" \
  "$ROOT/LookAway/Services/SleepWakeMonitor.swift" \
  "$ROOT/LookAway/Services/MenuBarWindowDismisser.swift" \
  "$ROOT/LookAway/Services/MenuBarWindowBackground.swift" \
  "$ROOT/LookAway/Services/BreakInputShield.swift" \
  "$ROOT/LookAway/Services/LaunchAtLoginManager.swift" \
  "$ROOT/LookAway/Views/MenuBarView.swift" \
  "$ROOT/LookAway/Views/MenuControls.swift" \
  "$ROOT/LookAway/Views/LookAwayDesign.swift" \
  "$ROOT/LookAway/Views/GlassStyles.swift" \
  "$ROOT/LookAway/Views/BreakOverlayView.swift" \
  "$ROOT/LookAway/Controllers/BreakOverlayController.swift"

cp "$ROOT/LookAway/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ICONSET="$ROOT/LookAway/Resources/AppIcon.iconset"
ICNS="$ROOT/LookAway/Resources/AppIcon.icns"
mkdir -p "$RESOURCES_DIR" "$(dirname "$ICONSET")"
swift "$ROOT/scripts/generate_app_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"
cp "$ICNS" "$RESOURCES_DIR/AppIcon.icns"

# Ensure Info.plist keys match the bundle layout
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.dvdcarlomagno.lookaway" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Look Away'" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Look Away'" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

ZIP_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}-${GIT_SHA}.zip"
(
  cd "$BUILD_DIR"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")"
)

echo ""
echo "Built: $APP_BUNDLE"
echo "Version: $VERSION ($BUILD_NUMBER / $GIT_SHA)"
echo "Zip:    $ZIP_PATH"

if [[ "${1:-}" == "--no-open" ]]; then
  echo "Run:   open \"$APP_BUNDLE\""
elif [[ "${1:-}" == "--zip-only" ]]; then
  echo "Zip-only build complete."
else
  open "$APP_BUNDLE"
  echo "Launched: $APP_BUNDLE"
fi
