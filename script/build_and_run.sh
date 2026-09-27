#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/TextUI.app"
BUNDLE_ID="com.r3d42.textui"
cd "$ROOT_DIR"

# A normal quit lets TextUI persist its drafts. Never force-kill the editor.
if /usr/bin/pgrep -x TextUI >/dev/null; then
  /usr/bin/osascript -e 'tell application id "com.r3d42.textui" to quit'
  for attempt in {1..50}; do
    if ! /usr/bin/pgrep -x TextUI >/dev/null; then break; fi
    sleep 0.1
  done
  if /usr/bin/pgrep -x TextUI >/dev/null; then
    echo "TextUI is still running. Finish closing it before rebuilding." >&2
    exit 1
  fi
fi

swift build --arch arm64 --product TextUI
BUILD_DIR="$(swift build --arch arm64 --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/TextUI" "$APP_BUNDLE/Contents/MacOS/TextUI"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
mkdir -p "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices"
for notice in "$ROOT_DIR"/Resources/ThirdPartyNotices/*.txt; do
  /usr/bin/install -m 644 "$notice" "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/"
done
/usr/bin/install -m 644 "$ROOT_DIR/LICENSE" "$ROOT_DIR/LICENSING.md" "$APP_BUNDLE/Contents/Resources/"
chmod +x "$APP_BUNDLE/Contents/MacOS/TextUI"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

if [[ "$MODE" == --build-only ]]; then
  echo "Built $APP_BUNDLE (local ad-hoc signature)."
  exit 0
fi

if [[ "$MODE" == --debug ]]; then
  exec /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/TextUI"
fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
  --verify)
    sleep 1
    /usr/bin/pgrep -x TextUI >/dev/null
    echo "TextUI process is running. This is not a visual UI test."
    ;;
  --logs)
    exec /usr/bin/log stream --info --style compact --predicate 'process == "TextUI"'
    ;;
  --telemetry)
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
esac
