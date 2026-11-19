#!/bin/bash
# Everything CI runs, cheapest failure first. `make ci` on a laptop runs the same thing.
source "$(dirname "$0")/lib/common.sh"
step() { printf '\n\033[1;35m===\033[0m %s\n' "$*"; }
DEV_DIR="$(resolve_developer_dir)"
[[ -n "$DEV_DIR" ]] && export DEVELOPER_DIR="$DEV_DIR"

step "Toolchain"; swift --version
step "No em or en dashes"
if grep -rnI $'\xe2\x80\x94\|\xe2\x80\x93' --exclude-dir=.build --exclude-dir=dist --exclude-dir=.git "$REPO_ROOT"; then
    die "em or en dash found; reword it"
fi
if command -v actionlint >/dev/null; then
    step "Workflows"; actionlint "$REPO_ROOT"/.github/workflows/*.yml
else
    warn "actionlint not installed; skipping workflow checks"
fi
step "Release notes"; "$REPO_ROOT/scripts/check-notes.sh" --allow-missing
step "Unit tests"; "$REPO_ROOT/scripts/test.sh"
step "Bundle"; "$REPO_ROOT/scripts/bundle.sh"
step "Verify bundle"; "$REPO_ROOT/scripts/verify-bundle.sh"
if command -v xcodegen >/dev/null && [[ -d "${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/Platforms" ]]; then
    step "App with widget (ad hoc)"
    SIGN=no "$REPO_ROOT/scripts/build-widget.sh"
    [[ -d "$APP_BUNDLE/Contents/PlugIns/WattsupWidget.appex" ]] || die "widget missing from the bundle"
    "$REPO_ROOT/scripts/verify-bundle.sh"
else
    warn "xcodegen or Xcode missing; skipping the widget build"
fi
info "All checks passed"
