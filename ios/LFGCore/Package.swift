// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LFGCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LFGCore", targets: ["LFGCore"]),
    ],
    targets: [
        .target(name: "LFGCore"),
        .testTarget(name: "LFGCoreTests", dependencies: ["LFGCore"]),
    ]
)
