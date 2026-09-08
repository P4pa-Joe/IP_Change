#!/usr/bin/env bash
# Builds "IP Change.app" (a proper macOS app bundle) from the Swift package.
#
# Usage: ./build-app.sh [destination-directory]
# Default destination: this script's directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${1:-$SCRIPT_DIR}"

APP_DISPLAY_NAME="IP Change"
APP_VERSION="26.2.1"
BUNDLE_ID="com.ipchange.app"
EXECUTABLE_NAME="IPChange"
# The product name swift build actually emits — matches the executableTarget
# name in Package.swift, which contains a space. Kept separate from
# EXECUTABLE_NAME (the name used inside the bundle) so the bundle's
# executable stays space-free while still finding the right build output.
SWIFT_PRODUCT_NAME="IP Change"

APP_BUNDLE="$DEST_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [ -d "$APP_BUNDLE" ]; then
    echo "Removing previous build at $APP_BUNDLE..."
    if pgrep -f "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" >/dev/null 2>&1; then
        echo "Quitting running instance..."
        pkill -f "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" || true
        sleep 1
    fi
    rm -rf "$APP_BUNDLE"
fi

echo "Building $APP_DISPLAY_NAME (release)..."
cd "$SCRIPT_DIR"
swift build -c release

BUILD_DATE="$(date +"%Y-%m-%d")"
SWIFT_VERSION="$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | awk '{print $3}')"

BIN_PATH="$(swift build -c release --show-bin-path)"
BUILT_BINARY="$BIN_PATH/$SWIFT_PRODUCT_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "error: built binary not found at $BUILT_BINARY" >&2
    exit 1
fi

echo "Creating app bundle at $APP_BUNDLE..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILT_BINARY" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# Reuse the existing app icon if present; the bundle is still valid without one.
ICON_SOURCE="$SCRIPT_DIR/Resources/AppIcon.icns"
ICON_NAME=""
ICON_KEY_XML=""
if [ -f "$ICON_SOURCE" ]; then
    ICON_NAME="AppIcon.icns"
    cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME"
    ICON_KEY_XML="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>IPChangeBuildDate</key>
    <string>$BUILD_DATE</string>
    <key>IPChangeSwiftVersion</key>
    <string>$SWIFT_VERSION</string>
$ICON_KEY_XML
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    echo "Signing with an ad-hoc identity..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "Done: $APP_BUNDLE"
open -R "$APP_BUNDLE"
