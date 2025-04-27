// swift-tools-version: 5.11
import PackageDescription

let package = Package(
    name: "SonosKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(
            name: "SonosKit",
            targets: ["SonosKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke", from: "12.8.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.6"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0"),
        .package(path: "../MusicSearchKit")
    ],
    targets: [
        .target(
            name: "SonosKit",
            dependencies: [
                "CloudStorage",
                "MusicSearchKit",
                .product(name: "Collections", package: "swift-collections")
            ]),
        .testTarget(
            name: "SonosKitTests",
            dependencies: [
                "SonosKit",
                .product(name: "Nuke", package: "nuke"),
                .product(name: "NukeUI", package: "nuke")
            ],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
