// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonosKit",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [
        .library(
            name: "SonosKit",
            targets: ["SonosKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/drmohundro/SWXMLHash", from: "7.0.0"),
        .package(path: "../MusicSearchKit")
    ],
    targets: [
        .target(
            name: "SonosKit",
            dependencies: [
                "SWXMLHash",
                "MusicSearchKit"
            ]),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            resources: [
                .copy("Resources/GetVolumeResponse.xml"),
                .copy("Resources/Zone.xml"),
                .copy("Resources/Track.xml"),
                .copy("Resources/GetPosition.xml"),
                .copy("Resources/RendererControl.xml"),
                .copy("Resources/AVTransport.xml"),
                .copy("Resources/GetTransportInfo.xml"),
                .copy("Resources/ZoneEvent.xml"),
                .copy("Resources/GetZoneGroupAttributes.xml"),
                .copy("Resources/GetQueue.xml"),
                .copy("Resources/GetCurrentTransportActions.xml")
            ]
        ),
    ]
)
