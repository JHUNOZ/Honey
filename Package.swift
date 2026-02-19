// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Honey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Honey",
            path: "Honey",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
