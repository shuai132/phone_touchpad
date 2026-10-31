#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_dir=".build/manual/TouchpadReceiver.app"
mkdir -p "$app_dir/Contents/MacOS"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx13.0" Shared/*.swift Mac/*.swift -o "$app_dir/Contents/MacOS/TouchpadReceiver"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchpadReceiver</string>
<key>CFBundleIdentifier</key><string>dev.phonetouchpad.receiver</string>
<key>CFBundleName</key><string>TouchpadReceiver</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>接收手机触控板操作。</string>
<key>NSBonjourServices</key><array><string>_phonetouchpad._tcp</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
