// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HueDatShared",
    platforms: [
        .macOS("15.0"),
        .iOS(.v17),
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
