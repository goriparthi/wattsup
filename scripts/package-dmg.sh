#!/bin/bash
# Builds dist/Wattsup-<version>.dmg, signed, and notarized when NOTARY_PROFILE is set.
source "$(dirname "$0")/lib/common.sh"
"$REPO_ROOT/scripts/bundle.sh"

DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGE="$DIST_DIR/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
info "Creating $DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

IDENTITY="$(find_signing_identity)"
[[ -n "$IDENTITY" ]] || { warn "Unsigned DMG: no Developer ID Application cert"; exit 0; }
codesign --force --sign "$IDENTITY" "$DMG"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    warn "Signed but not notarized; set NOTARY_PROFILE to a notarytool keychain profile"
    exit 0
fi
info "Submitting for notarization (this can take several minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
info "Notarized and stapled: $DMG"
