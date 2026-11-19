#!/bin/bash
# Builds, installs to ~/Applications and relaunches.
source "$(dirname "$0")/lib/common.sh"
"$REPO_ROOT/scripts/bundle.sh"
mkdir -p "$INSTALL_DIR"
pkill -f "$APP_NAME.app/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALLED_APP"
info "Installed $INSTALLED_APP"
open "$INSTALLED_APP"
