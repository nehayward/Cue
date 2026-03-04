// swift-tools-version: 5.11
import PackageDescription

let package = Package(
    name: "DropKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(
            name: "DropKit",
            targets: ["DropKit"]),
    ],
    targets: [
        .target(name: "DropKit"),
    ]
)
