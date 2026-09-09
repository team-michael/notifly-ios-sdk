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

(
  cd "$consumer_dir"
  xcodebuild build \
    -quiet \
    -scheme NotiflyKmpSdkSmokeHost \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO
)

echo "SwiftPM smoke host imports and calls NotiflyCore."
