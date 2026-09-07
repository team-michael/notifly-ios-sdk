#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSUMER_DIR="$ROOT_DIR/Tests/SwiftPMConsumer"
DERIVED_DATA="$ROOT_DIR/build/swiftpm-consumer"

rm -rf "$DERIVED_DATA"

cd "$CONSUMER_DIR"
xcodebuild \
  -quiet \
  -scheme NotiflySDKConsumer \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO

echo "SwiftPM consumer imports the public notifly_sdk module."
