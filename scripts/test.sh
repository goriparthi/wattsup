#!/bin/bash
# Runs the unit tests with a toolchain that has XCTest.
source "$(dirname "$0")/lib/common.sh"
cd "$REPO_ROOT"
DEV_DIR="$(resolve_developer_dir)"
[[ -n "$DEV_DIR" ]] || die "no developer dir found; install Xcode or the Command Line Tools"
DEVELOPER_DIR="$DEV_DIR" swift test "$@"
