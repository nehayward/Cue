// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchSync",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(
            name: "WatchSync",
            targets: ["WatchSync"]),
    ],
    targets: [
        .target(name: "WatchSync"),
        .testTarget(
            name: "WatchSyncTests",
            dependencies: ["WatchSync"]
        ),
    ]
)
