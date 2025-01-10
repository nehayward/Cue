// swift-tools-version: 5.11
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
        .package(url: "https://github.com/drmohundro/SWXMLHash", from: "8.0.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "2.0.0"))
    ],
    targets: [
        .target(
            name: "MusicSearchKit",
            dependencies: ["SWXMLHash", "SwiftyBeaver"]),
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
