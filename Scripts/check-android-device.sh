#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
android_sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -d "$android_sdk_path" ]] || { echo 'Set ANDROID_HOME to an installed Android SDK.' >&2; exit 1; }
case "$(uname -m)" in arm64) android_test_abi=arm64-v8a; android_test_arch=arm64;; x86_64) android_test_abi=x86_64; android_test_arch=x86_64;; *) echo 'Unsupported emulator host architecture.' >&2; exit 1;; esac
[[ -d "$android_sdk_path/system-images/android-34/google_apis/$android_test_abi" ]] || { echo 'Install the Android 34 Google APIs system image for this host architecture first.' >&2; exit 1; }
android_test_adb="$android_sdk_path/platform-tools/adb"
android_test_emulator="$android_sdk_path/emulator/emulator"
mkdir -p .build/android-device
android_test_artifacts="$PWD/.build/android-device"
android_test_dir="$(mktemp -d)"
android_test_emulator_pid=""
android_test_host_pid=""
android_test_serial=""
cleanup() {
    if [[ -n "$android_test_serial" && -n "$android_test_emulator_pid" ]] && kill -0 "$android_test_emulator_pid" 2>/dev/null; then
        "$android_test_adb" -s "$android_test_serial" emu kill >/dev/null 2>&1 || true
        kill "$android_test_emulator_pid" 2>/dev/null || true
        wait "$android_test_emulator_pid" 2>/dev/null || true
    fi
    if [[ -n "$android_test_host_pid" ]]; then kill "$android_test_host_pid" 2>/dev/null || true; wait "$android_test_host_pid" 2>/dev/null || true; fi
    rm -rf "$android_test_dir"
}
trap cleanup EXIT
bash android/gradlew -p android :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
swiftc Shared/*.swift Mac/Receiver.swift Mac/NativeGestures.swift Scripts/AndroidInteropHost.swift -o "$android_test_dir/host"
mkdir -p "$android_test_dir/avd/PhoneTouchpadTest.avd" "$android_test_dir/fixture"
cat > "$android_test_dir/avd/PhoneTouchpadTest.avd/config.ini" <<CONFIG
AvdId=PhoneTouchpadTest
avd.ini.displayname=Phone Touchpad Test
abi.type=$android_test_abi
hw.cpu.arch=$android_test_arch
hw.cpu.ncore=2
hw.ramSize=2048
hw.lcd.width=1080
hw.lcd.height=1920
hw.lcd.density=420
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.keyboard=yes
hw.camera.back=none
hw.camera.front=none
disk.dataPartition.size=2G
image.sysdir.1=system-images/android-34/google_apis/$android_test_abi/
tag.id=google_apis
tag.display=Google APIs
target=android-34
showDeviceFrame=no
skin.dynamic=yes
CONFIG
cat > "$android_test_dir/avd/PhoneTouchpadTest.ini" <<CONFIG
avd.ini.encoding=UTF-8
path=$android_test_dir/avd/PhoneTouchpadTest.avd
target=android-34
CONFIG
for android_test_port in 5562 5564 5566 5568 5570; do
    if ! "$android_test_adb" devices | awk 'NR>1 {print $1}' | rg -qx "emulator-$android_test_port"; then android_test_serial="emulator-$android_test_port"; break; fi
done
[[ -n "$android_test_serial" ]] || { echo 'No free test emulator port.' >&2; exit 1; }
env ANDROID_AVD_HOME="$android_test_dir/avd" "$android_test_emulator" -avd PhoneTouchpadTest -port "$android_test_port" -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader_indirect > "$android_test_artifacts/emulator.log" 2>&1 &
android_test_emulator_pid=$!
android_test_booted=false
for _ in {1..180}; do
    kill -0 "$android_test_emulator_pid" 2>/dev/null || { tail -30 "$android_test_artifacts/emulator.log"; exit 1; }
    if [[ "$("$android_test_adb" -s "$android_test_serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then android_test_booted=true; break; fi
    sleep 1
done
[[ "$android_test_booted" == true ]] || { echo 'Test emulator did not boot.' >&2; exit 1; }
"$android_test_adb" -s "$android_test_serial" shell input keyevent KEYCODE_WAKEUP
"$android_test_adb" -s "$android_test_serial" shell wm dismiss-keyguard
"$android_test_adb" -s "$android_test_serial" install -r android/app/build/outputs/apk/debug/app-debug.apk
"$android_test_adb" -s "$android_test_serial" install -r android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
"$android_test_dir/host" "$android_test_dir/fixture" 49271 300 > "$android_test_artifacts/device-host.log" 2>&1 &
android_test_host_pid=$!
for _ in {1..100}; do
    [[ -f "$android_test_dir/fixture/ready.json" ]] && break
    kill -0 "$android_test_host_pid" 2>/dev/null || { cat "$android_test_artifacts/device-host.log"; exit 1; }
    sleep 0.05
done
[[ -f "$android_test_dir/fixture/ready.json" ]] || { echo 'Cannot start isolated receiver; ensure TCP port 49271 is free.' >&2; exit 1; }
android_test_key="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key"])' "$android_test_dir/fixture/ready.json")"
"$android_test_adb" -s "$android_test_serial" shell am instrument -w -r -e pairingKey "$android_test_key" dev.phonetouchpad.android.test/androidx.test.runner.AndroidJUnitRunner > "$android_test_artifacts/device-tests.log"
cat "$android_test_artifacts/device-tests.log"
rg -q 'OK \(3 tests\)' "$android_test_artifacts/device-tests.log"
touch "$android_test_dir/fixture/done"
wait "$android_test_host_pid" || { cat "$android_test_artifacts/device-host.log"; exit 1; }
android_test_host_pid=""
cp "$android_test_dir/fixture/events.json" "$android_test_artifacts/device-events.json"
python3 - "$android_test_artifacts/device-events.json" <<'PY'
import json,sys
records=json.load(open(sys.argv[1]))
assert any(r['type']==18 and r['phase']==8 for r in records), 'Native rotation end was not received'
print('Android device rotation output verified at Mac receiver')
PY
cat "$android_test_artifacts/device-host.log"
for android_test_image in connect connected landscape; do
    "$android_test_adb" -s "$android_test_serial" exec-out run-as dev.phonetouchpad.android cat "files/$android_test_image.png" > "$android_test_artifacts/$android_test_image.png"
done
