#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -E 'github.com/(team-michael|notifly-tech)/notifly-kmp-sdk' "$ROOT_DIR/Package.swift" >/dev/null; then
  echo "SwiftPM exposes notifly-kmp-sdk to consumers" >&2
  exit 1
fi

grep -F '.binaryTarget(' "$ROOT_DIR/Package.swift" >/dev/null
grep -F 'path: "Artifacts/notifly_sdk.xcframework"' "$ROOT_DIR/Package.swift" >/dev/null
grep -F '@_exported import notifly_sdk' "$ROOT_DIR/Sources/NotiflySDKWrapper/Exports.swift" >/dev/null
grep -F "full.vendored_frameworks = 'Artifacts/notifly_sdk.xcframework'" "$ROOT_DIR/notifly_sdk.podspec" >/dev/null

if grep -E "dependency ['\"]NotiflyKMP['\"]" "$ROOT_DIR/notifly_sdk.podspec" >/dev/null; then
  echo "CocoaPods exposes NotiflyKMP to consumers" >&2
  exit 1
fi

swift package --package-path "$ROOT_DIR" dump-package >/dev/null
"$ROOT_DIR/scripts/test_swiftpm_consumer.sh"

echo "SwiftPM and CocoaPods expose only notifly_sdk at the package boundary."
