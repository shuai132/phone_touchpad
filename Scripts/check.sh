#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
Scripts/check-gesture-fixtures.sh
swiftc Shared/Protocol.swift Scripts/ProtocolCheck.swift -o "$check_dir/protocol"
"$check_dir/protocol"
swiftc Shared/*.swift Scripts/ScrollLiftCheck.swift -o "$check_dir/scrolllift"
"$check_dir/scrolllift"
swiftc Shared/*.swift Scripts/SamplingCheck.swift -o "$check_dir/sampling"
"$check_dir/sampling"
swiftc Shared/*.swift Scripts/GestureCheck.swift -o "$check_dir/gestures"
"$check_dir/gestures"
swiftc Shared/*.swift Scripts/SmartZoomCheck.swift -o "$check_dir/smartzoom"
"$check_dir/smartzoom"
swiftc Shared/*.swift Scripts/TransformCheck.swift -o "$check_dir/transforms"
"$check_dir/transforms"
swiftc Shared/*.swift Scripts/TapDragCheck.swift -o "$check_dir/tapdrag"
"$check_dir/tapdrag"
swiftc Shared/*.swift Scripts/PairingCheck.swift -o "$check_dir/pairing"
"$check_dir/pairing"
swiftc Shared/*.swift Mac/PairingQRCode.swift Scripts/QRCodeCheck.swift -o "$check_dir/qrcode"
"$check_dir/qrcode"
swiftc Mac/NativeGestures.swift Scripts/NativeGestureEncodingCheck.swift -o "$check_dir/nativeencoding"
"$check_dir/nativeencoding"
swiftc -typecheck Shared/*.swift Mac/*.swift
swiftc -typecheck Shared/*.swift iOS/Connection.swift
swiftc Shared/*.swift iOS/Connection.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/PairingRejectionCheck.swift -o "$check_dir/rejections"
"$check_dir/rejections"
swiftc Shared/*.swift iOS/Connection.swift Scripts/ConnectionCheck.swift -o "$check_dir/connection"
"$check_dir/connection"
# Syntax only: a full iOS SDK build still requires Xcode.
swiftc -frontend -parse iOS/*.swift
