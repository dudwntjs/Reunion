// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ReunionCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ReunionCore", targets: ["ReunionCore"])],
    targets: [
        .target(
            name: "ReunionCore",
            path: "Shared",
            exclude: ["ReunionAttributes.swift"],
            sources: ["ReunionCore.swift", "PlacesClient.swift", "Participants.swift"]
        ), .testTarget(name: "ReunionCoreTests", dependencies: ["ReunionCore"], path: "Tests/ReunionCoreTests"),
    ]
)
