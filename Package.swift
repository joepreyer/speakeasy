// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpeakEasy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpeakEasy",
            path: "Sources/SpeakEasy",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "SpeakEasyTests",
            dependencies: ["SpeakEasy"],
            path: "Tests/SpeakEasyTests"
        ),
    ]
)
