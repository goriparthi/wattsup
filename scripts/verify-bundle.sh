#!/bin/bash
# Checks dist/Wattsup.app is a bundle macOS will run and that it reports the right version.
source "$(dirname "$0")/lib/common.sh"
APP="${1:-$APP_BUNDLE}"
[[ -d "$APP" ]] || die "no bundle at $APP; run make bundle first"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "Info.plist is not valid"
codesign --verify --strict "$APP" || die "signature does not verify"
BIN_PATH="$APP/Contents/MacOS/$BIN_NAME"
REPORTED="$("$BIN_PATH" --version | awk '{print $2}')"
[[ "$REPORTED" == "$VERSION" ]] || die "bundle reports $REPORTED but Info.plist says $VERSION"
# 3 means no battery, which is expected on CI runners and desktops
set +e; "$BIN_PATH" --snapshot >/dev/null; code=$?; set -e
[[ $code == 0 || $code == 3 ]] || die "--snapshot failed with exit code $code"
info "Bundle OK ($VERSION)"
