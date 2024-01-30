// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SubscriptionKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SubscriptionKit",
            targets: ["SubscriptionKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "4.28.0"),
        .package(url: "https://github.com/nonstrict-hq/CloudStorage", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "SubscriptionKit",
            dependencies: [
                "CloudStorage",
                .product(name: "RevenueCat", package: "purchases-ios")
            ]
        ),
        .testTarget(
            name: "SubscriptionKitTests",
            dependencies: [
                "SubscriptionKit",
                "CloudStorage"
            ])
    ]
)
