#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MASTER="$PACKAGE_DIR/Resources/AppIcon-1024.png"
OUTPUT="$PACKAGE_DIR/Resources/AppIcon.icns"
BUILD_DIR="$PACKAGE_DIR/.icon-build"
ICONSET="$BUILD_DIR/AppIcon.iconset"

test -f "$MASTER"
test "$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/ {print $2}')" = "1024"
test "$(sips -g pixelHeight "$MASTER" | awk '/pixelHeight/ {print $2}')" = "1024"

rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET"
trap 'rm -rf "$BUILD_DIR"' EXIT

sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUTPUT"
test -s "$OUTPUT"
echo "$OUTPUT"
