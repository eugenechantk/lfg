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
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.0.0")),
    ],
    targets: [
        .target(
            name: "LFGCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "LFGCoreTests", dependencies: ["LFGCore"]),
    ]
)
