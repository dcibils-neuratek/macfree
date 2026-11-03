#!/bin/zsh
# Builds a release MacFree.app into ./build.
set -euo pipefail

cd "$(dirname "$0")/.."
app="build/MacFree.app"

swift build -c release
binary="$(swift build -c release --show-bin-path)/MacFree"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/MacFree"

iconset="$(mktemp -d)/MacFree.iconset"
swift scripts/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/MacFree.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>MacFree</string>
    <key>CFBundleExecutable</key><string>MacFree</string>
    <key>CFBundleIconFile</key><string>MacFree</string>
    <key>CFBundleIdentifier</key><string>com.diegocibils.macfree</string>
    <key>CFBundleName</key><string>MacFree</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSAppleEventsUsageDescription</key><string>MacFree asks Finder to empty the Trash when you request it.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
