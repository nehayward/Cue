// swift-tools-version: 6.0
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
        .package(url: "https://github.com/kean/Nuke", from: "13.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.6"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", .upToNextMajor(from: "0.23.0")),
        .package(path: "../MusicSearchKit"),
        .package(path: "../Defaults"),
        .package(path: "../DanceLogger")
    ],
    targets: [
        .target(
            name: "SonosKit",
            dependencies: [
                "CloudStorage",
                "MusicSearchKit",
                "DanceLogger",
                "FlyingFox",
                "Defaults",
                .product(name: "Collections", package: "swift-collections")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "SonosKitTests",
            dependencies: [
                "SonosKit",
                .product(name: "Nuke", package: "nuke"),
                .product(name: "NukeUI", package: "nuke")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
