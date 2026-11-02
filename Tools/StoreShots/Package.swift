// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StoreShots",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "storeshots", targets: ["StoreShots"]),
    ],
    targets: [
        .executableTarget(
            name: "StoreShots",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
