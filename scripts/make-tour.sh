#!/bin/zsh
# Rebuilds the website's stills and animated tour from sample data. Needs ffmpeg.
set -euo pipefail

cd "$(dirname "$0")/.."
work="$(mktemp -d)"

./scripts/record-stills.sh "$work/stills"
swiftc -O scripts/make-tour.swift -o "$work/make-tour"
"$work/make-tour" "$work/stills" "$work/frames"
ffmpeg -y -loglevel error -framerate 12 -i "$work/frames/%04d.png" \
  -vf "split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
  -loop 0 docs/images/tour.gif
cp "$work/stills/10-largest-selected.png" docs/images/select-and-delete.png
