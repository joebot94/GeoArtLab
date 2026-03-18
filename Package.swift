// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GeoArtLab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GeoArtLab", targets: ["GeoArtLab"])
    ],
    targets: [
        .executableTarget(
            name: "GeoArtLab"
        )
    ]
)
