#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
consumer_dir="$root_dir/Tests/NotiflyKmpSdkSmokeHost"
core_binary="$root_dir/build/NotiflyCore.xcframework/ios-arm64/NotiflyCore.framework/NotiflyCore"
derived_data="$(mktemp -d)"
trap 'rm -rf "$derived_data"' EXIT

file "$core_binary" | grep -F "dynamically linked shared library" >/dev/null

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
