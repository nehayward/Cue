// swift-tools-version: 5.10
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
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.6"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0"),
        .package(url: "https://github.com/drmohundro/SWXMLHash", from: "7.0.0"),
        .package(path: "../MusicSearchKit")
    ],
    targets: [
        .target(
            name: "SonosKit",
            dependencies: [
                "CloudStorage",
                "SWXMLHash",
                "MusicSearchKit",
                .product(name: "Collections", package: "swift-collections")
            ]),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            resources: [
                .copy("Resources/GetVolumeResponse.xml"),
                .copy("Resources/Zone.xml"),
                .copy("Resources/Track.xml"),
                .copy("Resources/GetPositionInfoApple.xml"),
                .copy("Resources/GetPositionInfoSpotify.xml"),
                .copy("Resources/GetPositionInfoSpotifyStream.xml"),
                .copy("Resources/RendererControl.xml"),
                .copy("Resources/AVTransport.xml"),
                .copy("Resources/GetTransportInfo.xml"),
                .copy("Resources/ZoneEvent.xml"),
                .copy("Resources/GetZoneGroupAttributes.xml"),
                .copy("Resources/GetQueue.xml"),
                .copy("Resources/GetQueueLarge.xml"),
                .copy("Resources/ZonesVanished.xml"),
                .copy("Resources/GetCurrentTransportActions.xml")
            ]
        ),
    ]
)
