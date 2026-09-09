#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcframework="$root_dir/build/NotiflyCore.xcframework"
release_dir="$root_dir/build/release"
archive="$release_dir/NotiflyCore.xcframework.zip"

if [[ ! -d "$xcframework" ]]; then
  echo "NotiflyCore.xcframework is missing. Run scripts/build_kmp_core_xcframework.sh first." >&2
  exit 1
fi

mkdir -p "$release_dir"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$xcframework" "$archive"

checksum="$(swift package compute-checksum "$archive")"
echo "archive=$archive"
echo "checksum=$checksum"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "archive=$archive"
    echo "checksum=$checksum"
  } >> "$GITHUB_OUTPUT"
fi
