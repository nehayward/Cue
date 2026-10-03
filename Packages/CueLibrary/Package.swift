// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CueLibrary",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(
            name: "CueLibrary",
            targets: ["CueLibrary"]),
    ],
    targets: [
        .target(name: "CueLibrary"),
        .testTarget(
            name: "CueLibraryTests",
            dependencies: ["CueLibrary"]
        ),
    ]
)
