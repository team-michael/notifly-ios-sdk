#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
consumer_dir="$root_dir/Tests/CoreConnectivity"
core_binary="$root_dir/Artifacts/NotiflyCore.xcframework/ios-arm64/NotiflyCore.framework/NotiflyCore"
derived_data="$(mktemp -d)"
trap 'rm -rf "$derived_data"' EXIT

file "$core_binary" | grep -F "dynamically linked shared library" >/dev/null

(
  cd "$consumer_dir"
  xcodebuild build \
    -quiet \
    -scheme CoreConnectivity \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO
)

echo "SwiftPM Core-only consumer imports and calls NotiflyCore."
