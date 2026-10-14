#!/bin/sh
# Builds "Smart Home.app" from this package, signs it ad-hoc for this Mac,
# and installs it. Usage:
#   scripts/install.sh               build and install into /Applications
#   scripts/install.sh --build-only  build .build/Smart Home.app only
set -eu

APP_NAME="Smart Home"
EXECUTABLE="SmartHomeMenuBar"
BUNDLE_ID="dev.leoglez.smart-home-local"
VERSION="0.1.0"
DESTINATION="/Applications"

case "${1:-}" in
    "") INSTALL=1 ;;
    --build-only) INSTALL=0 ;;
    *) echo "usage: scripts/install.sh [--build-only]" >&2; exit 64 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

swift build -c release --product "$EXECUTABLE"
BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"

APP="$ROOT/.build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Smart Home finds and controls your lights on your local network. Nothing leaves your network.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature: valid for this Mac only, no Apple Developer account needed.
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "Built: $APP"

if [ "$INSTALL" -eq 1 ]; then
    # Quit a running copy so the new binary replaces it cleanly.
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "$DESTINATION/$APP_NAME.app"
    ditto "$APP" "$DESTINATION/$APP_NAME.app"
    echo "Installed: $DESTINATION/$APP_NAME.app"
fi
