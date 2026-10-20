// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DynamicNotch",
            targets: ["DynamicNotch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DynamicNotch",
            path: "Sources/DynamicNotch",
            linkerSettings: [
                // Translation.framework ships with macOS 15+; weak-link it so the app still launches on macOS 14.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Translation"])
            ]
        )
    ]
)
