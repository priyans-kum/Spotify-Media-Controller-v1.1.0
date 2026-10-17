
#!/bin/bash
set -euo pipefail

APP_NAME="Spotify Media Controller"
EXECUTABLE="SpotifyMediaController"
BUNDLE_ID="com.spotifymediacontroller.mac"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking macOS build tools"

if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: Swift is not installed."
    echo "Install Xcode or the Xcode Command Line Tools first."
    exit 1
fi

echo "==> Building release executable"
swift build -c release

BINARY="$ROOT_DIR/.build/release/$EXECUTABLE"
PLIST="$ROOT_DIR/Resources/Info.plist"
APP="$ROOT_DIR/dist/$APP_NAME.app"

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Build succeeded but executable was not found:"
    echo "$BINARY"
    exit 1
fi

if [[ ! -f "$PLIST" ]]; then
    echo "ERROR: Resources/Info.plist was not found."
    exit 1
fi

echo "==> Preparing app bundle"
rm -rf "$APP"

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$PLIST" "$APP/Contents/Info.plist"

echo "==> Checking bundle identifier"
if ! /usr/libexec/PlistBuddy \
    -c "Print :CFBundleIdentifier" \
    "$APP/Contents/Info.plist" | grep -Fxq "$BUNDLE_ID"; then
    echo "ERROR: The bundle identifier in Info.plist is incorrect."
    exit 1
fi

echo "==> Applying ad-hoc code signature"
codesign --force --deep --sign - "$APP"

echo "==> Verifying app bundle"
codesign --verify --deep --strict "$APP"

/usr/libexec/PlistBuddy \
    -c "Print :CFBundleExecutable" \
    "$APP/Contents/Info.plist"

echo ""
echo "BUILD COMPLETE"
echo "App created at:"
echo "$APP"
echo ""
echo "This is a local testing build, not a notarized release."
