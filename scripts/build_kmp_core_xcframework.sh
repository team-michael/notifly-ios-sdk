#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$root_dir/core"
source_xcframework="$core_dir/build/XCFrameworks/release/NotiflyCore.xcframework"
output_dir="$root_dir/Artifacts"
output_xcframework="$output_dir/NotiflyCore.xcframework"

if [[ ! -x "$core_dir/gradlew" ]]; then
  echo "core submodule is not initialized. Run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" ]] && command -v brew >/dev/null 2>&1; then
  java_home="$(brew --prefix openjdk@17 2>/dev/null || true)/libexec/openjdk.jdk/Contents/Home"
  if [[ -x "$java_home/bin/java" ]]; then
    export JAVA_HOME="$java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
fi

APPLE_FRAMEWORK_NAME="NotiflyCore" \
APPLE_FRAMEWORK_IS_STATIC="false" \
"$core_dir/gradlew" \
  -p "$core_dir" \
  clean \
  assembleNotiflyCoreReleaseXCFramework \
  --no-daemon

test -d "$source_xcframework"
mkdir -p "$output_dir"
temporary_output="$(mktemp -d "$output_dir/.NotiflyCore.XXXXXX")"
trap 'rm -rf "$temporary_output"' EXIT
cp -R "$source_xcframework" "$temporary_output/NotiflyCore.xcframework"
find "$temporary_output/NotiflyCore.xcframework" -name Info.plist -type f -exec \
  perl -pi -e 's/[ \t]+$//' {} +

rm -rf "$output_xcframework"
mv "$temporary_output/NotiflyCore.xcframework" "$output_xcframework"

echo "$output_xcframework"
