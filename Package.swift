// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

var package = Package(
    name: "SwiftComponent",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SwiftComponent", targets: ["SwiftComponent"]),
        .plugin(name: "SwiftComponentBuildPlugin", targets: ["SwiftComponentBuildPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/yonaskolb/SwiftGUI", from: "0.2.2"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.0"),
        .package(url: "https://github.com/yonaskolb/swift-dependencies", branch: "merging"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", from: "1.2.4"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.0.0"),
        .package(url: "https://github.com/wickwirew/Runtime", from: "2.2.7"),
        .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0"),
        .package(url: "https://github.com/yonaskolb/AccessibilitySnapshot", revision: "1b5b7c0b0ffe5f8a3450c84751cd1260903d5e92"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/swiftui-navigation", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(name: "SwiftComponentCLI", dependencies: [
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .target(
            name: "SwiftComponent",
            dependencies: [
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "SwiftUINavigation", package: "swiftui-navigation"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                "SwiftGUI",
                "SwiftPreview",
                "Runtime",
                "SwiftComponentMacros",
            ]),
        .target(
            name: "SwiftPreview",
            dependencies: [
                .product(name: "AccessibilitySnapshotCore", package: "AccessibilitySnapshot", condition: .when(platforms: [.iOS])),
            ]),
        .testTarget(
            name: "SwiftComponentTests",
            dependencies: [
                "SwiftComponent",
            ]),
        .testTarget(
            name: "SwiftComponentMacroTests",
            dependencies: [
                "SwiftComponentMacros",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]),
        .plugin(name: "SwiftComponentBuildPlugin", capability: .buildTool(), dependencies: ["SwiftComponentCLI"]),
		.macro(
            name: "SwiftComponentMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
    ]
)
