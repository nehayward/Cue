// swift-tools-version: 5.11
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicSearchKit",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(
            name: "MusicSearchKit",
            type: .dynamic,
            targets: ["MusicSearchKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/drmohundro/SWXMLHash", from: "8.0.0"),
        .package(path: "../DanceLogger")
    ],
    targets: [
        .target(
            name: "MusicSearchKit",
            dependencies: ["SWXMLHash", "DanceLogger"],
            swiftSettings: [
//                .define("MUSICSEARCHKIT_VERBOSE_LOGGING")
            ]),
        .testTarget(
            name: "MusicSearchKitTests",
            dependencies: ["MusicSearchKit"],
            resources: [
                .process("Resources")
            ]),
    ]
)
