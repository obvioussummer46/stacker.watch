// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SNKit",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SNKit", targets: ["SNKit"])
    ],
    targets: [
        .target(name: "SNKit"),
        .testTarget(
            name: "SNKitTests",
            dependencies: ["SNKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
