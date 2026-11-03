#!/bin/zsh
# Renders the sample-data tour to Retina stills. Usage: scripts/record-stills.sh <output-folder>
# Liquid Glass can't be drawn off-screen, so this runs a temporary copy of the app with it turned off.
set -euo pipefail

cd "$(dirname "$0")/.."
output="${1:?Usage: record-stills.sh <output-folder>}"
copy="$(mktemp -d)/MacFree.app"

./scripts/build-app.sh
ditto build/MacFree.app "$copy"
/usr/libexec/PlistBuddy -c "Add :UIDesignRequiresCompatibility bool true" "$copy/Contents/Info.plist"
codesign --force --sign - "$copy"
mkdir -p "$output"
open -n -W --env MACFREE_RECORD="$output" "$copy" --args --demo
