// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Klopydrome",
    defaultLocalization: "en",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .library(name: "NavidromeClient", targets: ["NavidromeClient"]),
        .executable(name: "Klopydrome", targets: ["Klopydrome"])
    ],
    dependencies: [
        .package(path: "vendor/MPVKit-Audio")
    ],
    targets: [
        .target(
            name: "NavidromeClient",
            path: "Sources/NavidromeClient"
        ),
        .executableTarget(
            name: "Klopydrome",
            dependencies: [
                "NavidromeClient",
                .product(name: "MPVKit", package: "MPVKit-Audio")
            ],
            path: "Sources/Klopydrome",
            exclude: ["Assets.xcassets"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NavidromeClientTests",
            dependencies: [
                "NavidromeClient"
            ],
            path: "Tests/NavidromeClientTests"
        ),
        .testTarget(
            name: "KlopydromeTests",
            dependencies: [
                "Klopydrome"
            ],
            path: "Tests/KlopydromeTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
