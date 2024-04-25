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
            targets: ["notifly_sdk"]
        ),
    ],
    dependencies: [
        .package(name: "Firebase",
                 url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..."11.0.0"),
    ],
    targets: [
        .target(
            name: "notifly_sdk",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "Firebase"),
            ],
            path: "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk",
            sources: ["SourceCodes"],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ]
            
        ),
    ]
)
