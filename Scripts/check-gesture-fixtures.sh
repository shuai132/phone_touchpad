#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/Protocol.swift Shared/GestureEngine.swift Scripts/ExportGestureFixtures.swift -o "$check_dir/export"
"$check_dir/export" > "$check_dir/gestures.json"
python3 - "$check_dir/gestures.json" Tests/Fixtures/gestures.json <<'PY'
import json, math, sys
actual, expected = (json.load(open(path)) for path in sys.argv[1:])
def check(a, b, path='traces'):
    if isinstance(a, dict) and isinstance(b, dict):
        assert a.keys() == b.keys(), path
        for key in a: check(a[key], b[key], path + '.' + key)
    elif isinstance(a, list) and isinstance(b, list):
        assert len(a) == len(b), path
        for i, (x, y) in enumerate(zip(a, b)): check(x, y, f'{path}[{i}]')
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
        assert math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-7), path
    else: assert a == b, path
check(actual, expected)
print('Shared gesture fixture freshness check passed')
PY
