// swift-tools-version: 5.11
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VibesDS",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VibesDS",
            targets: ["VibesDS"]),
    ],
    dependencies: [
        .package(path: "../SonosKit"),
        .package(path: "../Defaults"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0"),
        .package(url: "https://github.com/kean/Nuke", from: "12.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "VibesDS",
            dependencies: [
                "CloudStorage",
                "SonosKit",
                "Defaults",
                .product(name: "NukeUI", package: "Nuke")
            ])
    ]
)
