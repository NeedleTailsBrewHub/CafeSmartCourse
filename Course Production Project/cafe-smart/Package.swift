// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "cafe-smart",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CafeSmart", type: .dynamic, targets: ["CafeSmart"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.5"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.18.1"),
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.3.2"),
        .package(url: "https://source.skip.dev/skip-stripe.git", "0.0.0"..<"2.0.0"),
        // Bootstrap / local: path. Production pin after VenueSmartKit v0.1.0 is published:
        // .package(url: "https://github.com/needletails/VenueSmartKit.git", from: "0.1.0"),
        .package(path: "../VenueSmartKit"),
    ],
    targets: [
        .target(name: "CafeSmart", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SkipStripe", package: "skip-stripe"),
            .product(name: "VenueSmartKit", package: "VenueSmartKit"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(
            name: "CafeSmartTests",
            dependencies: [
                "CafeSmart",
                .product(name: "VenueSmartKit", package: "VenueSmartKit"),
            ]
        ),
    ]
)
