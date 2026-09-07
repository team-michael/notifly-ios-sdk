#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="$ROOT_DIR/notifly-kmp-sdk"
OUTPUT="$ROOT_DIR/build/kmp/NotiflyKMP.xcframework"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
BUMP_WORKFLOW="$ROOT_DIR/.github/workflows/bump-kmp-submodule.yml"

if [[ ! -f "$ROOT_DIR/.gitmodules" ]]; then
  echo "Missing .gitmodules" >&2
  exit 1
fi

if [[ ! -e "$SUBMODULE_DIR/.git" ]]; then
  echo "Missing initialized notifly-kmp-sdk submodule" >&2
  exit 1
fi

EXPECTED_URL="https://github.com/notifly-tech/notifly-kmp-sdk.git"
ACTUAL_URL="$(git config -f "$ROOT_DIR/.gitmodules" --get submodule.notifly-kmp-sdk.url)"
if [[ "$ACTUAL_URL" != "$EXPECTED_URL" ]]; then
  echo "Expected KMP URL $EXPECTED_URL but found $ACTUAL_URL" >&2
  exit 1
fi

if ! KMP_TAG="$(git -C "$SUBMODULE_DIR" describe --tags --exact-match HEAD 2>/dev/null)"; then
  echo "notifly-kmp-sdk must point to an exact release tag" >&2
  exit 1
fi

[[ "$KMP_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
grep -F "submodules: recursive" "$CI_WORKFLOW" >/dev/null
grep -F "workflow_dispatch:" "$BUMP_WORKFLOW" >/dev/null
grep -F "https://github.com/notifly-tech/notifly-kmp-sdk.git" "$BUMP_WORKFLOW" >/dev/null
grep -F "gh workflow run ci.yml" "$BUMP_WORKFLOW" >/dev/null

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

"$SUBMODULE_DIR/gradlew" \
  -p "$SUBMODULE_DIR" \
  :kmp:iosSimulatorArm64Test \
  --no-daemon

"$ROOT_DIR/scripts/build_kmp_xcframework.sh"

if [[ ! -f "$OUTPUT/Info.plist" ]]; then
  echo "Missing $OUTPUT" >&2
  exit 1
fi

DEVICE_BINARY="$OUTPUT/ios-arm64/NotiflyKMP.framework/NotiflyKMP"
SIMULATOR_BINARY="$OUTPUT/ios-arm64_x86_64-simulator/NotiflyKMP.framework/NotiflyKMP"

file "$DEVICE_BINARY" | grep -F "current ar archive" >/dev/null
file "$SIMULATOR_BINARY" | grep -F "current ar archive" >/dev/null

xcrun lipo -archs "$DEVICE_BINARY" | grep -F "arm64" >/dev/null
xcrun lipo -archs "$SIMULATOR_BINARY" | grep -F "arm64" >/dev/null
xcrun lipo -archs "$SIMULATOR_BINARY" | grep -F "x86_64" >/dev/null

echo "Pinned static NotiflyKMP XCFramework is valid."
