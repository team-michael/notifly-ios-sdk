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
            targets: ["NotiflySDKWrapper"]
        )
    ],
    dependencies: [
        .package(
            name: "Firebase",
            url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..."20.0.0"),
    ],
    targets: [
        .target(
            name: "NotiflySDKWrapper",
            dependencies: [
                "notifly_sdk",
                .product(name: "FirebaseMessaging", package: "Firebase")
            ],
            path: "Sources/NotiflySDKWrapper"
        ),
        .binaryTarget(
            name: "notifly_sdk",
            path: "Artifacts/notifly_sdk.xcframework"
        ),
    ]
)
