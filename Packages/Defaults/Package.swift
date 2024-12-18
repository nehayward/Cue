// swift-tools-version: 5.11
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Defaults",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(
            name: "Defaults",
            targets: ["Defaults"]),
    ],
    targets: [
        .target(
            name: "Defaults")
    ]
)
