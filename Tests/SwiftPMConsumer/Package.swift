// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "NotiflySDKConsumer",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(name: "NotiflySDK", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "notifly_sdk", package: "NotiflySDK")
            ]
        )
    ]
)
