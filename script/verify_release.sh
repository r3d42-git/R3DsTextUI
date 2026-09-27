#!/bin/bash
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 VERSION ZIP" >&2; exit 64; }
VERSION="$1"
ZIP="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 64
[[ -f "$ZIP" && "$(basename "$ZIP")" == "TextUI-$VERSION-macOS-arm64.zip" ]] || exit 66
unzip -tq "$ZIP"
TEMP_DIR="$(mktemp -d /private/tmp/textui-verify.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto -x -k "$ZIP" "$TEMP_DIR"
APP="$TEMP_DIR/TextUI.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PLIST")" == com.r3d42.textui ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]]
[[ "$(lipo -archs "$APP/Contents/MacOS/TextUI")" == arm64 ]]
[[ -f "$APP/Contents/Resources/LICENSE" && -f "$APP/Contents/Resources/LICENSING.md" ]]
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$SIGNATURE"
[[ "$SIGNATURE" == *'Authority=Developer ID Application:'* && "$SIGNATURE" == *'TeamIdentifier=G6JH37W285'* && "$SIGNATURE" == *'(runtime)'* && "$SIGNATURE" == *'Timestamp='* ]]
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
echo "Verified TextUI $VERSION, arm64, Developer ID, attached ticket and Gatekeeper."
