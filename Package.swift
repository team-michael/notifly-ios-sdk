// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "NotiflySDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "NotiflySDK",
            targets: ["NotiflySDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "NotiflySDK",
            dependencies: [
                "Firebase",
                "FirebaseMessaging",
            ],
            path: "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk",
            sources: ["**/*"],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        ),
    ]
)
