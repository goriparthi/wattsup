#!/bin/bash
# Release notes must exist and read like notes, not a commit dump.
# Usage: scripts/check-notes.sh [version] [--allow-missing]
source "$(dirname "$0")/lib/common.sh"
WANT="$VERSION"; ALLOW_MISSING=0
for arg in "$@"; do
    case "$arg" in --allow-missing) ALLOW_MISSING=1 ;; *) WANT="$arg" ;; esac
done
NOTES="$REPO_ROOT/notes/releases/$WANT.md"
if [[ ! -f "$NOTES" ]]; then
    (( ALLOW_MISSING )) && { warn "no release notes yet at $NOTES"; exit 0; }
    die "write $NOTES before releasing"
fi
[[ $(wc -w < "$NOTES") -ge 15 ]] || die "$NOTES is too short to tell anyone what changed"
if grep -qE '^[0-9a-f]{7,40} ' "$NOTES"; then die "$NOTES reads like a commit log; write it for people"; fi
info "Release notes for $WANT look fine"
