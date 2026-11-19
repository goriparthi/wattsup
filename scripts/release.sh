#!/bin/bash
# Publishes a GitHub release: checks notes and a clean tree, tests, builds a notarized DMG,
# uploads it. The in-app updater refuses anything not notarized, so this does too.
source "$(dirname "$0")/lib/common.sh"
command -v gh >/dev/null || die "gh CLI not found"
[[ -z "${1:-}" || "$1" == "$VERSION" ]] || die "asked for $1 but Resources/Info.plist says $VERSION"
TAG="v$VERSION"

git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet \
    || die "working tree is dirty; commit before releasing"
# A CI checkout is the remote commit by definition and has no upstream branch to compare
if [[ "${RELEASE_FROM_CI:-0}" != "1" ]]; then
    [[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse @{u} 2>/dev/null)" ]] \
        || die "push first; gh release create tags the remote's HEAD"
fi
gh release view "$TAG" >/dev/null 2>&1 && die "$TAG is already released; bump the version"
"$REPO_ROOT/scripts/check-notes.sh" "$VERSION"

"$REPO_ROOT/scripts/test.sh"
"$REPO_ROOT/scripts/package-dmg.sh"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
spctl -a -t install "$DMG" 2>/dev/null || die "$(basename "$DMG") is not notarized; set NOTARY_PROFILE"

# Create first, then upload with retries: a flaky network once failed the combined call
gh release create "$TAG" --title "$APP_NAME $VERSION" --target "$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    --notes-file "$REPO_ROOT/notes/releases/$VERSION.md"
for attempt in 1 2 3 4; do
    gh release upload "$TAG" "$DMG" --clobber && break
    [[ $attempt == 4 ]] && die "upload failed four times; the release exists without its DMG"
    warn "upload attempt $attempt failed; retrying"
    sleep 5
done
info "Released: $(gh release view "$TAG" --json url --jq .url)"
gh release list --limit 3
