// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "notifly_sdk",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "notifly_sdk",
            targets: ["Notifly"]
        ),
    ],
    dependencies: [
        .package(name: "Firebase",
                 url: "https://github.com/firebase/firebase-ios-sdk.git",
                 from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "Notifly",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "Firebase"),
            ],
            path: "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk",
            sources: ["SourceCodes"]
        ),
    ]
)
