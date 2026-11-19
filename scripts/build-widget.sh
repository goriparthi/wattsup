#!/bin/bash
# Builds Wattsup.app with its desktop widget through Xcode, then signs inside out.
# SwiftPM cannot build app extensions, which is why this path exists.
source "$(dirname "$0")/lib/common.sh"
cd "$REPO_ROOT"
DEV_DIR="$(resolve_developer_dir)"
[[ -d "$DEV_DIR/Platforms" ]] || die "Xcode is required to build the widget"
command -v xcodegen >/dev/null || die "xcodegen not found; brew install xcodegen"

# Always regenerate: the project lists files explicitly, so a new source file would go missing
xcodegen generate --quiet
DERIVED="$DIST_DIR/xcode"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"

# Build unsigned and sign ourselves: Xcode would pick a Development identity and add
# get-task-allow, both of which notarization rejects
info "Building $APP_NAME $VERSION with widget"
DEVELOPER_DIR="$DEV_DIR" xcodebuild -project Wattsup.xcodeproj -scheme "$APP_NAME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet
[[ -d "$BUILT" ]] || die "build reported success but $BUILT is missing"

IDENTITY="${SIGN:-yes}"
SIGN_ARGS=(--force)
if [[ "$IDENTITY" == "no" ]]; then
    SIGN_ARGS+=(--sign -)
elif ID="$(find_signing_identity)" && [[ -n "$ID" ]]; then
    info "Signing with: $ID"
    SIGN_ARGS+=(--sign "$ID" --options runtime --timestamp)
else
    warn "No Developer ID; signing ad-hoc (runs here only)"
    SIGN_ARGS+=(--sign -)
fi

# Nested code is sealed before what contains it: framework, extension, app
codesign "${SIGN_ARGS[@]}" "$BUILT/Contents/Frameworks/WattsupCore.framework"
codesign "${SIGN_ARGS[@]}" --entitlements Sources/WattsupWidget/WattsupWidget.entitlements \
    --identifier com.goriparthi.wattsup.widget "$BUILT/Contents/PlugIns/WattsupWidget.appex"
codesign "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID" "$BUILT"

if codesign -d --entitlements - "$BUILT" 2>/dev/null | grep -q "get-task-allow"; then
    die "get-task-allow present; notarization would reject this build"
fi
codesign --verify --strict "$BUILT" || die "signature verification failed"
codesign -d --entitlements - --xml "$BUILT/Contents/PlugIns/WattsupWidget.appex" 2>/dev/null | grep -q app-sandbox \
    || die "the widget must be sandboxed or macOS will not register it"

rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"
cp -R "$BUILT" "$APP_BUNDLE"
# A copy left in DerivedData would register a second widget with Launch Services
rm -rf "$BUILT"
info "Built $APP_BUNDLE with Contents/PlugIns/WattsupWidget.appex"
