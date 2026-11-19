#!/bin/bash
# Shared names, paths and helpers for every script. Sourced, not executed.
set -euo pipefail

APP_NAME="Wattsup"
BIN_NAME="wattsup"
BUNDLE_ID="com.goriparthi.wattsup"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$REPO_ROOT/Resources/Info.plist" 2>/dev/null || echo "0.0.0")"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# XCTest ships with Xcode, not the Command Line Tools, so prefer Xcode when both exist
resolve_developer_dir() {
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then echo "$DEVELOPER_DIR"; return; fi
    local selected
    selected="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$selected" == *"CommandLineTools"* && -d /Applications/Xcode.app ]]; then
        echo "/Applications/Xcode.app/Contents/Developer"
    else
        echo "$selected"
    fi
}

# Developer ID is required for notarized downloads; ad-hoc only runs locally
find_signing_identity() {
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then echo "$CODESIGN_IDENTITY"; return; fi
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}
