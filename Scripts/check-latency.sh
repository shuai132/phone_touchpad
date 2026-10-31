#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
latency_check_dir="$(mktemp -d)"
trap 'rm -rf "$latency_check_dir"' EXIT
swiftc -O Shared/*.swift iOS/Connection.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/InputLatencyCheck.swift -o "$latency_check_dir/latency"
"$latency_check_dir/latency"
