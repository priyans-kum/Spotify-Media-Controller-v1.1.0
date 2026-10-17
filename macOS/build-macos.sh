#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS. It cannot build a macOS app on Windows."
  exit 2
fi

mkdir -p dist
swift build -c release --triple arm64-apple-macosx14.2

APP="dist/SpotifyMediaController.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/arm64-apple-macosx14.2/release/SpotifyMediaController" "$APP/Contents/MacOS/SpotifyMediaController"
chmod +x "$APP/Contents/MacOS/SpotifyMediaController"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SpotifyMediaController</string>
    <key>CFBundleIdentifier</key>
    <string>com.priyanskum.SpotifyMediaController</string>
    <key>CFBundleName</key>
    <string>Spotify Media Controller</string>
    <key>CFBundleDisplayName</key>
    <string>Spotify Media Controller</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Spotify Media Controller monitors audio activity from other applications so it can pause Spotify while other media is playing. Audio is analyzed locally and is not saved or transmitted.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Spotify Media Controller sends play and pause commands to the Spotify desktop app when needed.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/SpotifyMediaController-macOS-arm64.zip"

echo
echo "Build complete:"
echo "  $APP"
echo "  $SCRIPT_DIR/dist/SpotifyMediaController-macOS-arm64.zip"
echo
echo "This is an ad-hoc signed development build. It is not notarized."
