#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexMenuBar"
BUNDLE_ID="dev.benjamin.codex-menubar"
BUNDLE_NAME="Codex Menu Bar"
VERSION="0.3.11"
BUILD_NUMBER="14"
ICON_NAME="AppIcon.icns"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SOURCE="$PACKAGE_DIR/Resources/$ICON_NAME"
DIST_DIR="$PACKAGE_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "App icon was not found at $ICON_SOURCE" >&2
    exit 1
fi

BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"
swift build --package-path "$PACKAGE_DIR" -c release

EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Build succeeded but executable was not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$BUNDLE_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>$BUNDLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
