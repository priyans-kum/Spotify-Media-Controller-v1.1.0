// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyMediaController",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SpotifyMediaController", targets: ["SpotifyMediaController"])
    ],
    targets: [
        .executableTarget(
            name: "SpotifyMediaController",
            path: "Sources/SpotifyMediaController"
        )
    ]
)
