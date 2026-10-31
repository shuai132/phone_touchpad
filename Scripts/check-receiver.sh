#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/*.swift iOS/Connection.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/ReceiverCheck.swift -o "$check_dir/receiver"
"$check_dir/receiver"
