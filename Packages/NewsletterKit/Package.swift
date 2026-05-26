// swift-tools-version: 5.11
import PackageDescription

let package = Package(
    name: "NewsletterKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(
            name: "NewsletterKit",
            targets: ["NewsletterKit"]),
    ],
    targets: [
        .target(name: "NewsletterKit"),
    ]
)
