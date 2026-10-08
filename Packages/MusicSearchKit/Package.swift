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
        // 7.x as well as 8.x: TIDAL's SDK (in the app) is on 7.x, and one
        // package graph can hold only one. Nothing here uses what 8 added.
        .package(url: "https://github.com/drmohundro/SWXMLHash", "7.0.2"..<"9.0.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "2.0.0"))
    ],
    targets: [
        .target(
            name: "MusicSearchKit",
            dependencies: ["SWXMLHash", "SwiftyBeaver"],
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
