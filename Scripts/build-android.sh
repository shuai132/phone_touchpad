#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash android/gradlew -p android :app:assembleDebug :app:lintDebug :core:test --console=plain
