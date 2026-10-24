// swift-tools-version: 5.10
import PackageDescription

// Shared by the app, its CarPlay scene and the widget extension: data, caches and the small SwiftUI pieces.
let package = Package(
    name: "CarburantsKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CarburantsKit", targets: ["CarburantsKit"]),
    ],
    targets: [
        .target(
            name: "CarburantsKit",
            resources: [
                .copy("Resources/Logos"),
                .copy("Resources/brand_logos.json"),
            ]
        ),
        .testTarget(
            name: "CarburantsKitTests",
            dependencies: ["CarburantsKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
