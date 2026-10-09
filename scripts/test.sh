#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Swift Build loses the Testing macro plugin when it rebuilds the tests after a Core change, so its folder is named outright.
plugins="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/host/plugins/testing"
flags=()
if [ -d "$plugins" ]; then flags=(-Xswiftc -plugin-path -Xswiftc "$plugins"); fi

# SwiftPM always adds the XCTest search paths, which Command Line Tools do not ship, so the linker warns about them.
swift test "${flags[@]}" "$@" 2>&1 \
    | { grep -v "search path '/Library/Developer/CommandLineTools/Developer/.*' not found" || true; }
exit "${PIPESTATUS[0]}"
