// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Muzzle",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Muzzle", targets: ["Muzzle"])
    ],
    targets: [
        .executableTarget(name: "Muzzle", path: "Sources/Muzzle"),
        .testTarget(name: "MuzzleTests", dependencies: ["Muzzle"], path: "Tests/MuzzleTests")
    ]
)
