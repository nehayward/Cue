// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicSearchKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "MusicSearchKit",
            targets: ["MusicSearchKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/drmohundro/SWXMLHash", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "MusicSearchKit",
            dependencies: ["SWXMLHash"]),
        .testTarget(
            name: "MusicSearchKitTests",
            dependencies: ["MusicSearchKit"],
            resources: [
                .copy("Resources/cryYourHeartOutSearch.json"),
                .copy("Resources/duaLipaSpotifyPlaylistsResponse.json"),
                .copy("Resources/plex_search_dance.xml")
            ]),
    ]
)
