// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotiflyKmpSdkSmokeHost",
    platforms: [.iOS(.v15)],
    dependencies: [
        .package(name: "notifly_sdk", path: "../..")
    ],
    targets: [
        .testTarget(
            name: "NotiflyKmpSdkSmokeHostTests",
            dependencies: [
                .product(name: "NotiflyCore", package: "notifly_sdk")
            ]
        )
    ]
)
