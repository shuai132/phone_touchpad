#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
web_pinch_dir="$(mktemp -d)"
trap 'rm -rf "$web_pinch_dir"' EXIT
mkdir -p "$web_pinch_dir/WebPinchTarget.app/Contents/MacOS"
swiftc Scripts/WebPinchTarget.swift -parse-as-library -o "$web_pinch_dir/WebPinchTarget.app/Contents/MacOS/WebPinchTarget"
cat > "$web_pinch_dir/WebPinchTarget.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>WebPinchTarget</string><key>CFBundleIdentifier</key><string>dev.phonetouchpad.webpinchtarget</string><key>CFBundleName</key><string>Touchpad Web Pinch Test</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc Shared/*.swift iOS/Connection.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/WebPinchCheck.swift -o "$web_pinch_dir/check"
"$web_pinch_dir/check" "$web_pinch_dir"
