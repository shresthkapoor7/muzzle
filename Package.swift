// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebsiteBlocker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WebsiteBlocker", targets: ["WebsiteBlocker"])
    ],
    targets: [
        .executableTarget(name: "WebsiteBlocker"),
        .testTarget(name: "WebsiteBlockerTests", dependencies: ["WebsiteBlocker"])
    ]
)
