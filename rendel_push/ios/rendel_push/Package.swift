// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "rendel_push",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "rendel-push", targets: ["rendel_push"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "rendel_push",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // The device token, for the app's own pushes; nothing else.
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
