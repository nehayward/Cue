// swift-tools-version: 5.11
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Analytics",
    products: [
        .library(name: "Analytics", targets: ["Analytics"])
    ],
    dependencies: [
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "4.0.4"),
    ],
    targets: [
        .target(
            name: "Analytics",
            dependencies: [
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ]
        )
    ]
)
