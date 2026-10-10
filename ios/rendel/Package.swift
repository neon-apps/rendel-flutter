// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "rendel",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "rendel", targets: ["rendel"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "rendel",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // It uses no required-reason API and collects nothing; the
                // manifest says so, which is what App Review reads.
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
