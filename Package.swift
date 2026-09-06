// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "notifly_sdk",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "notifly_sdk",
            targets: ["notifly_sdk"]
        )
    ],
    dependencies: [
        .package(
            name: "Firebase",
            url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..."20.0.0"),
        .package(
            name: "NotiflyKMP",
            url: "https://github.com/team-michael/notifly-kmp-sdk.git",
            .exact("0.1.0-alpha.2")
        )
    ],
    targets: [
        .target(
            name: "notifly_sdk",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "Firebase"),
                .product(name: "NotiflyKMP", package: "NotiflyKMP")
            ],
            path: "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk",
            sources: ["SourceCodes", "PrivacyInfo.xcprivacy"]
        )
    ]
)
