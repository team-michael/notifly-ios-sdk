#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk.xcodeproj/project.pbxproj"
USER_MANAGER="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/Infrastructures/User/UserManager.swift"

if grep -F 'github.com/team-michael/notifly-kmp-sdk' "$ROOT_DIR/Package.swift" >/dev/null; then
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
grep -F 'Build NotiflyKMP' "$PROJECT_FILE" >/dev/null
grep -F -- '-force_load' "$PROJECT_FILE" >/dev/null

echo "NotiflyKMP is configured as an internal Xcode implementation dependency."
