#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
DRY_RUN=0
if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=1; shift; fi
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 [--dry-run] VERSION" >&2; exit 64; }
REPO=r3d42-git/R3DsTextUI
TAG="v$VERSION"
OUT="$ROOT_DIR/dist/release/$VERSION"
NAME="TextUI-$VERSION-macOS-arm64.zip"
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]]
[[ "$(git rev-parse HEAD)" == "$(cat "$OUT/source-commit.txt")" ]]
REMOTE="$(git remote get-url origin)"
[[ "$REMOTE" == "https://github.com/$REPO.git" || "$REMOTE" == "git@github.com:$REPO.git" ]]
[[ "$(gh repo view "$REPO" --json visibility --jq .visibility)" == PUBLIC ]]
[[ -z "$(git tag -l "$TAG")" && -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ]]
(cd "$OUT" && shasum -a 256 -c "$NAME.sha256")
"$ROOT_DIR/script/verify_release.sh" "$VERSION" "$OUT/$NAME"
[[ -f "release-notes/$TAG.md" ]]
if [[ "$DRY_RUN" == 1 ]]; then echo 'Dry-run passed; no remote changes.'; exit 0; fi
git push -u origin main
git tag -a "$TAG" -m "TextUI $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$OUT/$NAME" "$OUT/$NAME.sha256" --repo "$REPO" --verify-tag --title "TextUI $VERSION" --notes-file "release-notes/$TAG.md"
DOWNLOAD="$(mktemp -d /private/tmp/textui-download.XXXXXX)"
echo "Independent download: $DOWNLOAD"
gh release download "$TAG" --repo "$REPO" --pattern "$NAME*" --dir "$DOWNLOAD"
cmp "$OUT/$NAME.sha256" "$DOWNLOAD/$NAME.sha256"
(cd "$DOWNLOAD" && shasum -a 256 -c "$NAME.sha256")
LOCAL_SHA="$(shasum -a 256 "$OUT/$NAME" | cut -d ' ' -f1)"
REMOTE_SHA="$(gh api "repos/$REPO/releases/tags/$TAG" --jq ".assets[] | select(.name == \"$NAME\") | .digest")"
[[ "$REMOTE_SHA" == "sha256:$LOCAL_SHA" ]]
"$ROOT_DIR/script/verify_release.sh" "$VERSION" "$DOWNLOAD/$NAME"
echo "Published and independently verified https://github.com/$REPO/releases/tag/$TAG"
