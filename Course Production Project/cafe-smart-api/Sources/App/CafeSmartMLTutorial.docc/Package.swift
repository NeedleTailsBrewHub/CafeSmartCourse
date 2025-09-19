// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CafeSmartMLTutorial",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "CafeSmartMLTutorial",
            targets: ["CafeSmartMLTutorial"]),
    ],
    dependencies: [
        // Dependencies go here
    ],
    targets: [
        .target(
            name: "CafeSmartMLTutorial",
            dependencies: []),
        .testTarget(
            name: "CafeSmartMLTutorialTests",
            dependencies: ["CafeSmartMLTutorial"]),
    ]
)
