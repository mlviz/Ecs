// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Ecs",
    products: [
        .library(
            name: "Ecs",
            targets: ["Ecs"]
        ),
    ],
    targets: [
        .target(
            name: "Ecs"
        ),
        .testTarget(
            name: "EcsTests",
            dependencies: ["Ecs"]
        )
    ]
)
