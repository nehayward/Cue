// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DanceLogger",
    platforms: [.iOS(.v15), .macOS(.v12), .watchOS(.v8), .tvOS(.v15), .visionOS(.v1)],
    products: [
        // Dynamic, so a process holds one copy however many of its frameworks
        // log: one `DanceLogStore.shared`, one writer per file. Linked
        // statically into an app and a framework, each would get its own.
        .library(
            name: "DanceLogger",
            type: .dynamic,
            targets: ["DanceLogger"]),
    ],
    targets: [
        .target(name: "DanceLogger"),
        .testTarget(
            name: "DanceLoggerTests",
            dependencies: ["DanceLogger"]
        ),
    ]
)
