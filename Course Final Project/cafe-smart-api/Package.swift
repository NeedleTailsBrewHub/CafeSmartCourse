// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CafeSmartApi",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", .upToNextMajor(from: "7.9.4")),
        .package(url: "https://github.com/vapor/jwt.git", .upToNextMajor(from: "5.0.0")),
    ],
    targets: [
        .executableTarget(
            name: "CafeSmartApi",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "Meow", package: "MongoKitten"),
                .product(name: "JWT", package: "jwt"),
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
