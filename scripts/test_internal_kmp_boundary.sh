#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk.xcodeproj/project.pbxproj"
USER_MANAGER="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/Infrastructures/User/UserManager.swift"
PROJECT="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk.xcodeproj"

if grep -E 'github.com/(team-michael|notifly-tech)/notifly-kmp-sdk' "$ROOT_DIR/Package.swift" >/dev/null; then
  echo "Package.swift exposes notifly-kmp-sdk" >&2
  exit 1
fi

if grep -E "dependency ['\"]NotiflyKMP['\"]" "$ROOT_DIR/notifly_sdk.podspec" >/dev/null; then
  echo "notifly_sdk.podspec exposes NotiflyKMP" >&2
  exit 1
fi

if grep -F 'XCRemoteSwiftPackageReference "notifly-kmp-sdk"' "$PROJECT_FILE" >/dev/null; then
  echo "Xcode project exposes a remote notifly-kmp-sdk package" >&2
  exit 1
fi

grep -F '@_implementationOnly import NotiflyKMP' "$USER_MANAGER" >/dev/null

if grep -F 'Build NotiflyKMP' "$PROJECT_FILE" >/dev/null; then
  echo "Xcode builds NotiflyKMP instead of consuming the prepared framework" >&2
  exit 1
fi

BUILD_SETTINGS="$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme notifly-ios-sdk \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -showBuildSettings
)"

grep -E 'KMP_FRAMEWORK_DIR = .*/build/kmp/NotiflyKMP\.xcframework/ios-arm64_x86_64-simulator$' <<<"$BUILD_SETTINGS" >/dev/null
grep -E 'FRAMEWORK_SEARCH_PATHS = .*"?.*/build/kmp/NotiflyKMP\.xcframework/ios-arm64_x86_64-simulator"?' <<<"$BUILD_SETTINGS" >/dev/null
grep -E 'OTHER_LDFLAGS = .* -force_load "?.*/NotiflyKMP\.framework/NotiflyKMP"?$' <<<"$BUILD_SETTINGS" >/dev/null

echo "Xcode consumes the prepared NotiflyKMP framework as an internal implementation dependency."
