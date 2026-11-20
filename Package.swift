// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Ribbon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ribbon",
            path: "Sources/Ribbon",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
