#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
interop_host_pid=""
cleanup() {
    if [[ -n "$interop_host_pid" ]]; then kill "$interop_host_pid" 2>/dev/null || true; wait "$interop_host_pid" 2>/dev/null || true; fi
    rm -rf "$check_dir"
}
trap cleanup EXIT
swiftc Shared/*.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/AndroidInteropHost.swift -o "$check_dir/host"
"$check_dir/host" "$check_dir" > "$check_dir/host.log" 2>&1 &
interop_host_pid=$!
for _ in {1..100}; do
    [[ -f "$check_dir/ready.json" ]] && break
    kill -0 "$interop_host_pid" 2>/dev/null || { cat "$check_dir/host.log"; exit 1; }
    sleep 0.05
done
[[ -f "$check_dir/ready.json" ]] || { cat "$check_dir/host.log"; exit 1; }
bash android/gradlew -p android :core:test --tests '*MacInteropTest' -PinteropFile="$check_dir/ready.json" --console=plain --rerun-tasks
wait "$interop_host_pid" || { cat "$check_dir/host.log"; exit 1; }
interop_host_pid=""
cat "$check_dir/host.log"
