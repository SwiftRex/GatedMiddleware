// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GatedMiddleware",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "GatedMiddleware", targets: ["GatedMiddleware"])
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftRex/SwiftRex.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "GatedMiddleware", dependencies: [.product(name: "CombineRex", package: "SwiftRex")]),
        .testTarget(name: "GatedMiddlewareTests", dependencies: ["GatedMiddleware"])
    ]
)
