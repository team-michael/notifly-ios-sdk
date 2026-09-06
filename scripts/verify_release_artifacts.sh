#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK="$ROOT_DIR/Artifacts/notifly_sdk.xcframework"

if [[ ! -f "$XCFRAMEWORK/Info.plist" ]]; then
  echo "Missing release artifact: $XCFRAMEWORK" >&2
  exit 1
fi

DEVICE_FRAMEWORK="$XCFRAMEWORK/ios-arm64/notifly_sdk.framework"
SIMULATOR_FRAMEWORK="$XCFRAMEWORK/ios-arm64_x86_64-simulator/notifly_sdk.framework"

for framework in "$DEVICE_FRAMEWORK" "$SIMULATOR_FRAMEWORK"; do
  if [[ ! -f "$framework/notifly_sdk" ]]; then
    echo "Missing framework binary: $framework/notifly_sdk" >&2
    exit 1
  fi

  interface_count="$(find "$framework/Modules" -name '*.swiftinterface' -type f | wc -l | tr -d ' ')"
  if [[ "$interface_count" -eq 0 ]]; then
    echo "No Swift interfaces found in $framework" >&2
    exit 1
  fi

  if grep -R -F 'NotiflyKMP' "$framework/Modules" --include='*.swiftinterface' >/dev/null; then
    echo "NotiflyKMP leaked into the public Swift interface in $framework" >&2
    exit 1
  fi

  if grep -R -E '^import Firebase(Core|Messaging)$' "$framework/Modules" --include='*.swiftinterface' >/dev/null; then
    echo "Firebase implementation modules leaked into the public Swift interface in $framework" >&2
    exit 1
  fi

  if otool -L "$framework/notifly_sdk" | grep -F 'NotiflyKMP' >/dev/null; then
    echo "notifly_sdk has a runtime dependency on NotiflyKMP in $framework" >&2
    exit 1
  fi

  if ! nm -gU "$framework/notifly_sdk" | grep -F 'UserIdTransitionPolicy' >/dev/null; then
    echo "KMP policy symbols were not linked into $framework" >&2
    exit 1
  fi
done

xcrun lipo -archs "$DEVICE_FRAMEWORK/notifly_sdk" | grep -F 'arm64' >/dev/null
xcrun lipo -archs "$SIMULATOR_FRAMEWORK/notifly_sdk" | grep -F 'arm64' >/dev/null
xcrun lipo -archs "$SIMULATOR_FRAMEWORK/notifly_sdk" | grep -F 'x86_64' >/dev/null

if ! find "$XCFRAMEWORK" -name PrivacyInfo.xcprivacy -type f | grep -q .; then
  echo "PrivacyInfo.xcprivacy is missing from the release artifact" >&2
  exit 1
fi

echo "Release XCFramework contains KMP internally without exposing it to consumers."
