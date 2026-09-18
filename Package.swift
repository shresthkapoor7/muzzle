// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Muzzle",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Muzzle", targets: ["Muzzle"]),
        .executable(name: "MuzzleHelper", targets: ["MuzzleHelper"])
    ],
    targets: [
        .target(name: "MuzzleService", path: "Sources/MuzzleService"),
        .executableTarget(name: "Muzzle", dependencies: ["MuzzleService"], path: "Sources/Muzzle"),
        .executableTarget(name: "MuzzleHelper", dependencies: ["MuzzleService"], path: "Sources/MuzzleHelper"),
        .testTarget(name: "MuzzleTests", dependencies: ["Muzzle", "MuzzleService"], path: "Tests/MuzzleTests"),
        .testTarget(name: "MuzzleHelperTests", dependencies: ["MuzzleHelper", "MuzzleService"])
    ]
)
