// swift-tools-version:6.3
import PackageDescription

let package = Package(
  name: "cafe-smart-api",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    // 💧 A server-side Swift web framework.
    .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
    // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
    .package(url: "https://github.com/brokenhandsio/VaporSecurityHeaders.git", .upToNextMajor(from: "4.2.0")),
    .package(url: "https://github.com/swiftpackages/DotEnv.git", .upToNextMajor(from: "3.0.0")),
    .package(url: "https://github.com/orlandos-nl/MongoKitten.git", .upToNextMajor(from: "7.16.3")),
    .package(url: "https://github.com/vapor/jwt.git", from: "5.1.2"),
    // Post-quantum ML-DSA JWTs (`@_spi(PostQuantum)` / MLDSA87PrivateKey).
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.6.0"),
    .package(url: "https://github.com/needletails/binary-codable.git", from: "1.1.0"),
    .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.3.1"),
    .package(url: "https://github.com/NeedleTailsBrewHub/swift-onnx-runtime.git", from: "1.0.1")
  ],
  targets: [
    .executableTarget(
      name: "cafe-smart-api",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOWebSocket", package: "swift-nio"),
        .product(name: "MongoKitten", package: "MongoKitten"),
        .product(name: "Meow", package: "MongoKitten"),
        .product(name: "VaporSecurityHeaders", package: "VaporSecurityHeaders"),
        .product(name: "JWT", package: "jwt"),
        .product(name: "JWTKit", package: "jwt-kit"),
        .product(name: "BinaryCodable", package: "binary-codable"),
        .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
        .product(name: "DotEnv", package: "DotEnv"),
        .product(name: "CONNX", package: "swift-onnx-runtime", condition: .when(platforms: [.linux, .macOS]))
      ],
      path: "Sources/App",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "ApiTests",
      dependencies: [
        .target(name: "cafe-smart-api")
      ],
      swiftSettings: swiftSettings
    ),
  ]
)

var swiftSettings: [SwiftSetting] {
  [
    .enableUpcomingFeature("ExistentialAny")
  ]
}
