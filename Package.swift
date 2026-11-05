// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Holler",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Speech recognition only: no text-to-speech, diarization or text normalization.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2", traits: []),
    ],
    targets: [
        .target(
            name: "HollerKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Holler",
            dependencies: ["HollerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test suite as a plain executable: XCTest and Swift Testing don't run with
        // the Command Line Tools alone. Run with `swift run HollerChecks`.
        .executableTarget(
            name: "HollerChecks",
            dependencies: ["HollerKit"],
            path: "Checks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
