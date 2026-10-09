#!/bin/zsh
# Usage: run-probe.sh <probe-main.swift> [args…]
# Builds the real app sources plus a probe main in a throwaway package outside the repo, in release, and runs it.
set -e -o pipefail
here=${0:A:h}
repo=${here:h:h}
work=${HARDYDO_PROBE_DIR:-${TMPDIR:-/tmp}/hardydo-notes-probe}
mkdir -p "$work/Sources/AppProbe"
cp "$repo/Package.swift" "$work/Package.swift"
sed -i '' -e 's/name: "HardydoNotes", dependencies/name: "AppProbe", dependencies/' \
          -e '/testTarget/d' "$work/Package.swift"
ln -sfn "$repo/Sources/HardydoNotesCore" "$work/Sources/HardydoNotesCore"
rsync -a --delete --exclude HardydoNotesApp.swift --exclude main.swift "$repo/Sources/HardydoNotes/" "$work/Sources/AppProbe/"
cp "${1:A}" "$work/Sources/AppProbe/main.swift"
shift
cd "$work"
swift build -c release --product AppProbe 2>&1 | grep -E "error:|Build complete" | head -20
"./.build/release/AppProbe" "$@"
