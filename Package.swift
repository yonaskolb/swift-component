// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftComponent",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "SwiftComponent",
            targets: ["SwiftComponent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.6.0"),
        .package(url: "https://github.com/yonaskolb/SwiftGUI", from: "0.1.1"),
    ],
    targets: [
        .target(
            name: "SwiftComponent",
            dependencies: [.product(name: "CustomDump", package: "swift-custom-dump"), "SwiftGUI"]),
        .testTarget(
            name: "SwiftComponentTests",
            dependencies: ["SwiftComponent"]),
    ]
)
