// swift-tools-version:5.5
import Foundation
import PackageDescription

// Updated by scripts/prepare_kmp_core_release.rb when an iOS SDK release is created.
let releasedCoreVersion = "LOCAL"
let releasedCoreChecksum = "0000000000000000000000000000000000000000000000000000000000000000"
let localCorePath = "build/NotiflyCore.xcframework"

let coreBinaryTarget: Target
if FileManager.default.fileExists(atPath: localCorePath) || releasedCoreVersion == "LOCAL" {
    coreBinaryTarget = .binaryTarget(
        name: "NotiflyCore",
        path: localCorePath
    )
} else {
    coreBinaryTarget = .binaryTarget(
        name: "NotiflyCore",
        url: "https://github.com/team-michael/notifly-ios-sdk/releases/download/\(releasedCoreVersion)/NotiflyCore.xcframework.zip",
        checksum: releasedCoreChecksum
    )
}

let package = Package(
    name: "notifly_sdk",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "notifly_sdk",
            targets: ["notifly_sdk"]
        ),
        .library(
            name: "NotiflyCore",
            targets: ["NotiflyCore"]
        )
    ],
    dependencies: [
        .package(
            name: "Firebase",
            url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..."20.0.0")
    ],
    targets: [
        .target(
            name: "notifly_sdk",
            dependencies: [
                "NotiflyCore",
                .product(name: "FirebaseMessaging", package: "Firebase")
            ],
            path: "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk",
            sources: ["SourceCodes", "PrivacyInfo.xcprivacy"]
        ),
        coreBinaryTarget
    ]
)
