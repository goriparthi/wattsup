#!/bin/bash
# Publishes a GitHub release: checks notes and a clean tree, tests, builds a notarized DMG,
# uploads it. The in-app updater refuses anything not notarized, so this does too.
source "$(dirname "$0")/lib/common.sh"
command -v gh >/dev/null || die "gh CLI not found"
[[ -z "${1:-}" || "$1" == "$VERSION" ]] || die "asked for $1 but Resources/Info.plist says $VERSION"
TAG="v$VERSION"

git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet \
    || die "working tree is dirty; commit before releasing"
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse @{u} 2>/dev/null)" ]] \
    || die "push first; gh release create tags the remote's HEAD"
gh release view "$TAG" >/dev/null 2>&1 && die "$TAG is already released; bump the version"
"$REPO_ROOT/scripts/check-notes.sh" "$VERSION"

"$REPO_ROOT/scripts/test.sh"
"$REPO_ROOT/scripts/package-dmg.sh"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
spctl -a -t install "$DMG" 2>/dev/null || die "$(basename "$DMG") is not notarized; set NOTARY_PROFILE"

gh release create "$TAG" "$DMG" --title "$APP_NAME $VERSION" \
    --notes-file "$REPO_ROOT/notes/releases/$VERSION.md"
info "Released: $(gh release view "$TAG" --json url --jq .url)"
gh release list --limit 3
