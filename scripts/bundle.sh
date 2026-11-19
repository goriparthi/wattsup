#!/bin/bash
# Assembles dist/Wattsup.app from the release binary and signs it.
source "$(dirname "$0")/lib/common.sh"
"$REPO_ROOT/scripts/build.sh"

info "Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/release/$BIN_NAME" "$APP_BUNDLE/Contents/MacOS/$BIN_NAME"
cp "$REPO_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
[[ -f "$REPO_ROOT/Resources/Wattsup.icns" ]] && cp "$REPO_ROOT/Resources/Wattsup.icns" "$APP_BUNDLE/Contents/Resources/"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

IDENTITY="$(find_signing_identity)"
if [[ -n "$IDENTITY" ]]; then
    info "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"
else
    warn "No Developer ID Application cert found; signing ad-hoc (runs locally only)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi
codesign --verify --strict "$APP_BUNDLE" && info "Signature verified"
