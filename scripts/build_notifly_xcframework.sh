#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk.xcodeproj"
SCHEME="notifly-ios-sdk"
BUILD_ROOT="$ROOT_DIR/build/release-xcframework"
DEVICE_ARCHIVE="$BUILD_ROOT/notifly_sdk-iphoneos.xcarchive"
SIMULATOR_ARCHIVE="$BUILD_ROOT/notifly_sdk-iphonesimulator.xcarchive"
OUTPUT_DIR="$ROOT_DIR/Artifacts"
OUTPUT="$OUTPUT_DIR/notifly_sdk.xcframework"
PRIVACY_MANIFEST="$ROOT_DIR/Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/PrivacyInfo.xcprivacy"
SOURCE_PACKAGES="$ROOT_DIR/build/SourcePackages"

"$ROOT_DIR/scripts/build_kmp_xcframework.sh"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES"

archive_framework() {
  local destination="$1"
  local archive_path="$2"
  local derived_data_path="$3"

  xcodebuild archive \
    -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "$destination" \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
    -disableAutomaticPackageResolution \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    PRODUCT_NAME=notifly_sdk \
    PRODUCT_MODULE_NAME=notifly_sdk
}

archive_framework "generic/platform=iOS" "$DEVICE_ARCHIVE" "$BUILD_ROOT/DerivedData-iphoneos"
archive_framework "generic/platform=iOS Simulator" "$SIMULATOR_ARCHIVE" "$BUILD_ROOT/DerivedData-iphonesimulator"

DEVICE_FRAMEWORK="$DEVICE_ARCHIVE/Products/Library/Frameworks/notifly_sdk.framework"
SIMULATOR_FRAMEWORK="$SIMULATOR_ARCHIVE/Products/Library/Frameworks/notifly_sdk.framework"

for framework in "$DEVICE_FRAMEWORK" "$SIMULATOR_FRAMEWORK"; do
  if [[ ! -d "$framework" ]]; then
    echo "Archive did not contain $framework" >&2
    exit 1
  fi
  cp "$PRIVACY_MANIFEST" "$framework/PrivacyInfo.xcprivacy"
done

TEMP_OUTPUT="$(mktemp -d "$OUTPUT_DIR/.notifly_sdk.XXXXXX")"
trap 'rm -rf "$TEMP_OUTPUT"' EXIT

xcodebuild -create-xcframework \
  -framework "$DEVICE_FRAMEWORK" \
  -framework "$SIMULATOR_FRAMEWORK" \
  -output "$TEMP_OUTPUT/notifly_sdk.xcframework"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT/notifly_sdk.xcframework" "$OUTPUT"

echo "$OUTPUT"
