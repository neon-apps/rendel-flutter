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
        // Reading aloud's PCM output: flutter_pcm_sound's Objective-C, which a
        // Swift target cannot hold, so it is a target of its own.
        .target(
            name: "rendel_pcm",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .target(
            name: "rendel",
            dependencies: [
                "rendel_pcm",
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
