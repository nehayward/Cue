// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibesDS",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14), .tvOS(.v18)],
    products: [
        .library(
            name: "VibesDS",
            targets: ["VibesDS"]
        ),
    ],
    dependencies: [
        .package(path: "../SonosKit"),
        .package(path: "../Defaults"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0"),
        .package(url: "https://github.com/kean/Nuke", from: "13.0.0")
    ],
    targets: [
        .target(
            name: "VibesDS",
            dependencies: [
                "CloudStorage",
                "SonosKit",
                "Defaults",
                .product(name: "NukeUI", package: "Nuke")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
