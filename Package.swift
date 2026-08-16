// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacSnip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacSnip",
            targets: ["MacSnip"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacSnip",
            dependencies: [],
            path: "Sources/MacSnip",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
