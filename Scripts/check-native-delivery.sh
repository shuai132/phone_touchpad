#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
mkdir -p "$check_dir/GestureTarget.app/Contents/MacOS"
swiftc Scripts/GestureTarget.swift -parse-as-library -o "$check_dir/GestureTarget.app/Contents/MacOS/GestureTarget"
cat > "$check_dir/GestureTarget.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>GestureTarget</string><key>CFBundleIdentifier</key><string>dev.phonetouchpad.gesturetarget</string><key>CFBundleName</key><string>Touchpad Gesture Test</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc Mac/NativeGestures.swift Scripts/NativeGestureDeliveryCheck.swift -o "$check_dir/delivery"
"$check_dir/delivery" "$check_dir"
