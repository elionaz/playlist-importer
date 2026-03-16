// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaylistImporter",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PlaylistImporter",
            path: "Sources/PlaylistImporter",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PlaylistImporterTests",
            dependencies: ["PlaylistImporter"],
            path: "Tests/PlaylistImporterTests"
        )
    ]
)
