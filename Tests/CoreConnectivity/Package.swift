// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreConnectivity",
    platforms: [.iOS(.v15)],
    dependencies: [
        .package(name: "notifly_sdk", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "CoreConnectivity",
            dependencies: [
                .product(name: "NotiflyCore", package: "notifly_sdk")
            ]
        )
    ]
)
