// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "CafeSmartApi",
    platforms: [
       .macOS(.v26)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", .upToNextMajor(from: "7.16.3")),
        .package(url: "https://github.com/vapor/jwt.git", .upToNextMajor(from: "5.0.0")),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.6.0"),
        .package(url: "https://github.com/needletails/binary-codable.git", from: "1.1.0"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.3.1"),
        .package(path: "Vendor/swift-onnx-runtime"),
    ],
    targets: [
        .executableTarget(
            name: "CafeSmartApi",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "Meow", package: "MongoKitten"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "BinaryCodable", package: "binary-codable"),
                .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
                .product(name: "CONNX", package: "swift-onnx-runtime", condition: .when(platforms: [.linux, .macOS])),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CafeSmartApiTests",
            dependencies: [
                .target(name: "CafeSmartApi"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
