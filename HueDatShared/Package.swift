// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HueDatShared",
    platforms: [
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "HueDatShared",
            targets: ["HueDatShared"]),
    ],
    targets: [
        .target(
            name: "HueDatShared",
            dependencies: [])
    ]
)
