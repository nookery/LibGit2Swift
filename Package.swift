// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LibGit2Swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LibGit2Swift",
            targets: ["LibGit2Swift"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/bdewey/static-libgit2.git", from: "0.5.0"),
        .package(url: "https://github.com/nookery/MagicLog.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LibGit2Swift",
            dependencies: [
                .product(name: "static-libgit2", package: "static-libgit2"),
                .product(name: "MagicLog", package: "MagicLog"),
            ]),
        .testTarget(
            name: "LibGit2SwiftTests",
            dependencies: ["LibGit2Swift"])
    ]
)
