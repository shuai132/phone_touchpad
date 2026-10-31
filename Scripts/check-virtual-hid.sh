#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
virtual_hid_probe_dir="$(mktemp -d)"
trap 'rm -rf "$virtual_hid_probe_dir"' EXIT
swiftc -target "$(uname -m)-apple-macosx26.0" Scripts/VirtualHIDProbe.swift -parse-as-library -o "$virtual_hid_probe_dir/probe"
"$virtual_hid_probe_dir/probe"
