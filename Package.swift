// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RateLimiter",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(
            name: "RateLimiter",
            targets: ["RateLimiter"]),
        .library(
            name: "RateLimiterHummingbird",
            targets: ["RateLimiterHummingbird"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "RateLimiter",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "RateLimiterHummingbird",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                "RateLimiter",
            ]
        ),
        .testTarget(
            name: "RateLimiterTests",
            dependencies: ["RateLimiter"]
        ),
    ]
)
