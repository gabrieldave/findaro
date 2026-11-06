// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orden",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Orden", targets: ["OrdenApp"]),
        .library(name: "OrdenCore", targets: ["OrdenCore"])
    ],
    targets: [
        .target(
            name: "OrdenCore",
            path: "Sources/OrdenCore"
        ),
        .executableTarget(
            name: "OrdenApp",
            dependencies: ["OrdenCore"],
            path: "Sources/OrdenApp"
        ),
        .testTarget(
            name: "OrdenTests",
            dependencies: ["OrdenCore"],
            path: "Tests/OrdenTests"
        )
    ]
)
