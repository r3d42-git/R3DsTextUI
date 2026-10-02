#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 VERSION" >&2; exit 64; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)" == "$VERSION" ]]
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit all source changes before release.' >&2; exit 1; }
# Fingerprint selects the G2 certificate even when Developer ID names match.
IDENTITY="${SIGNING_IDENTITY:-D548540E7FE1BD9B3C4518CC02D8786E1BFEB885}"
PROFILE="${NOTARY_PROFILE:-TextUI}"
IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"$IDENTITY"* ]] || { echo 'Developer ID identity unavailable.' >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
OUT="$ROOT_DIR/dist/release/$VERSION"
[[ ! -e "$OUT" ]] || { echo "Output exists; preserve it and choose a fresh output/version: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/source-commit.txt"
swift test --arch arm64 > "$OUT/tests.log" 2>&1
swift build -c release --arch arm64 --product TextUI
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
APP="$OUT/TextUI.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ThirdPartyNotices"
install -m755 "$BIN/TextUI" "$APP/Contents/MacOS/TextUI"
install -m644 Resources/Info.plist "$APP/Contents/Info.plist"
install -m644 Resources/AppIcon.icns LICENSE LICENSING.md "$APP/Contents/Resources/"
install -m644 Resources/ThirdPartyNotices/*.txt "$APP/Contents/Resources/ThirdPartyNotices/"
codesign --force --sign "$IDENTITY" --timestamp --options runtime "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$OUT/submitted.zip"
xcrun notarytool submit "$OUT/submitted.zip" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notarization.json"
STATUS="$(plutil -extract status raw "$OUT/notarization.json")"
if [[ "$STATUS" != Accepted ]]; then
  ID="$(plutil -extract id raw "$OUT/notarization.json")"
  xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$OUT/notarization-log.json"
  echo "Notarization failed: $STATUS ($ID)" >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
NAME="TextUI-$VERSION-macOS-arm64.zip"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$OUT/$NAME"
"$ROOT_DIR/script/verify_release.sh" "$VERSION" "$OUT/$NAME"
(cd "$OUT" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Release ready: $OUT/$NAME"
