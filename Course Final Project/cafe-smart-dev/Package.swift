// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "cafe-smart-dev",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CafeSmartDev", type: .dynamic, targets: ["CafeSmartDev"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.30"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.3.0"),
        .package(url: "https://github.com/orlandos-nl/BSON.git", from: "8.2.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.2.0"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.2.0")
    ],
    targets: [
        .target(name: "CafeSmartDev", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "BSON", package: "BSON"),
            .product(name: "JWTKit", package: "jwt-kit"),
            .product(name: "ConnectionManagerKit", package: "connection-manager-kit")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
