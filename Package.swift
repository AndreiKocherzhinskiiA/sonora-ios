// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Sonora",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // An xtool project contains exactly one library product, the main app.
        .library(name: "Sonora", targets: ["Sonora"]),
    ],
    targets: [
        .target(
            name: "Sonora",
            path: "Sonora",
            exclude: [
                // Xcode-only: the asset catalog, plist and fonts. xtool cannot compile catalogs,
                // so icons ship as PNGs from scripts/rasterize-icons.sh and the fonts, app icon
                // and Info.plist keys come from xtool.yml.
                "Assets.xcassets",
                "Supporting",
                "Resources/Fonts",
            ],
            resources: [
                .copy("Resources/Icons"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
