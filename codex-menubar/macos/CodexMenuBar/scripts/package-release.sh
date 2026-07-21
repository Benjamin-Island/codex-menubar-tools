#!/usr/bin/env bash
set -euo pipefail

VERSION="0.2.0"
APP_NAME="CodexMenuBar"
BUNDLE_ID="dev.benjamin.codex-menubar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ASSET_NAME="$APP_NAME-v$VERSION-apple-silicon.zip"
ASSET_PATH="$DIST_DIR/$ASSET_NAME"

"$SCRIPT_DIR/build-app.sh"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" = "$BUNDLE_ID"
test "$(lipo -archs "$EXECUTABLE_PATH")" = "arm64"
codesign --verify --deep --strict "$APP_PATH"

rm -f "$ASSET_PATH" "$ASSET_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ASSET_PATH"
(
    cd "$DIST_DIR"
    shasum -a 256 "$ASSET_NAME" > "$ASSET_NAME.sha256"
)

echo "$ASSET_PATH"
echo "$ASSET_PATH.sha256"
