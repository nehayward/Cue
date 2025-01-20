// swift-tools-version: 5.11
import PackageDescription

let package = Package(
    name: "SonosKitMini",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SonosKitMini",
            targets: ["SonosKitMini"]),
    ],
    targets: [
        .target(name: "SonosKitMini"),
        .testTarget(
            name: "SonosKitMiniTests",
            dependencies: ["SonosKitMini"],
            resources: [
                .copy("Resources/Zone.xml"),
                .copy("Resources/ZoneRaw.xml"),
                .copy("Resources/ZoneWithBoost.xml"),
                .copy("Resources/ZonesVanished.xml"),
                .copy("Resources/Track.xml")
            ]
        ),
    ]
)
