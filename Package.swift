// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Notifly",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "Notifly",
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
