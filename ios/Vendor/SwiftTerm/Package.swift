// swift-tools-version:5.9
// Vendored SwiftTerm v1.11.2 (b1262db5b6bea699a8260a8c66999436c508ca56), MIT.
// Library target only. Local patches are listed in PATCHES.md.

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.iOS(.v13), .macOS(.v13)],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"]
        ),
    ]
)
