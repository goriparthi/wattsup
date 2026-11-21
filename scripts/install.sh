#!/bin/bash
# Builds, installs to ~/Applications and relaunches.
source "$(dirname "$0")/lib/common.sh"
# With Xcode the bundle carries the desktop widget; without it, the plain SwiftPM bundle
if [[ -d /Applications/Xcode.app ]] && command -v xcodegen >/dev/null; then
    "$REPO_ROOT/scripts/build-widget.sh"
else
    warn "Xcode or xcodegen missing: building without the desktop widget"
    "$REPO_ROOT/scripts/bundle.sh"
fi
mkdir -p "$INSTALL_DIR"
pkill -f "$APP_NAME.app/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALLED_APP"
info "Installed $INSTALLED_APP"
"$REPO_ROOT/scripts/xprotect-scan.sh" "$INSTALLED_APP"
open "$INSTALLED_APP"
