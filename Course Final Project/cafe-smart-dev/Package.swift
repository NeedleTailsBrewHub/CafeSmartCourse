// swift-tools-version: 6.3
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "cafe-smart-dev",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CafeSmartDev", type: .dynamic, targets: ["CafeSmartDev"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.5"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.18.1"),
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.3.2"),
        .package(url: "https://github.com/needletails/binary-codable.git", from: "1.1.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.6.0"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.3.1")
    ],
    targets: [
        .target(name: "CafeSmartDev", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "BinaryCodable", package: "binary-codable"),
            .product(name: "JWTKit", package: "jwt-kit"),
            .product(name: "ConnectionManagerKit", package: "connection-manager-kit")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
