#!/usr/bin/env bash
# Exercise the actual AppKit picker without launching or registering Selby.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product selby-tests
BIN_DIR="$(swift build --show-bin-path)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/selby-picker-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -I "$BIN_DIR/Modules" \
  "$BIN_DIR"/SelbyCore.build/*.swift.o \
  Sources/Selby/PickerPanel.swift Sources/Selby/BrowserPickerView.swift \
  Sources/SelbyUITests/main.swift -o "$TEST_DIR/picker-tests"
"$TEST_DIR/picker-tests"
