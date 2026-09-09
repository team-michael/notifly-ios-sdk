#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
consumer_dir="$root_dir/Tests/NotiflyKmpSdkSmokeHost"
xcframework="$root_dir/build/NotiflyCore.xcframework"
derived_data="$(mktemp -d)"
trap 'rm -rf "$derived_data"' EXIT

for slice in ios-arm64 ios-arm64_x86_64-simulator; do
  framework="$xcframework/$slice/NotiflyCore.framework"
  file "$framework/NotiflyCore" | grep -F "dynamically linked shared library" >/dev/null
  expected_platform="iPhoneOS"
  if [[ "$slice" == *-simulator ]]; then
    expected_platform="iPhoneSimulator"
  fi
  actual_platform="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$framework/Info.plist")"
  if [[ "$actual_platform" != "$expected_platform" ]]; then
    echo "$slice declares $actual_platform; expected $expected_platform." >&2
    exit 1
  fi
done

simulator_id="${SIMULATOR_ID:-}"
if [[ -z "$simulator_id" ]]; then
  simulator_id="$(xcrun simctl list devices available -j | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices")
      .select { |runtime, _| runtime.include?(".iOS-") }
      .values.flatten
      .select { |device| device["isAvailable"] && device["name"].start_with?("iPhone") }
    device = devices.find { |candidate| candidate["state"] == "Booted" } || devices.first
    abort "No available iPhone simulator found for the Core runtime test." unless device
    puts device.fetch("udid")
  ')"
fi

(
  cd "$consumer_dir"
  xcodebuild test \
    -quiet \
    -scheme NotiflyKmpSdkSmokeHost-Package \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO
)

echo "SwiftPM runtime test imported NotiflyCore and received a Core function result."
