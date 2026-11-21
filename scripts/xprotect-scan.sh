#!/bin/bash
# Scans built binaries with Apple's own XProtect rules and fails on any match. Byte rules can match
# compiled code by coincidence, and a match gets the app killed and trashed on users' Macs.
# Usage: scripts/xprotect-scan.sh [path ...]   (defaults to dist/Wattsup.app)
source "$(dirname "$0")/lib/common.sh"
RULES=/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.yara
command -v yara >/dev/null || die "yara not installed (brew install yara); refusing to skip the XProtect scan"
[[ -f "$RULES" ]] || die "XProtect rules not found at $RULES"
TARGETS=("$@")
[[ ${#TARGETS[@]} -gt 0 ]] || TARGETS=("$APP_BUNDLE")
found=0
while IFS= read -r -d '' bin; do
    if file -b "$bin" | grep -q "Mach-O"; then
        hits="$(yara -w "$RULES" "$bin" 2>/dev/null || true)"
        if [[ -n "$hits" ]]; then
            warn "XProtect rule matched: $hits"
            found=1
        fi
    fi
done < <(find "${TARGETS[@]}" -type f -perm -u+x -print0)
(( found == 0 )) || die "a binary matches an XProtect rule; change the code layout and rebuild before shipping"
info "XProtect scan clean ($(yara --version 2>/dev/null | head -1), rules $(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString 2>/dev/null))"
