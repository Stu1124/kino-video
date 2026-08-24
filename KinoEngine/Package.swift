// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinoEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "KinoEngine", targets: ["KinoEngine"]),
    ],
    targets: [
        .target(
            name: "KinoEngine",
            path: "Sources/KinoEngine"
        ),
        .testTarget(
            name: "KinoEngineTests",
            dependencies: ["KinoEngine"],
            path: "Tests/KinoEngineTests"
        ),
    ]
)
