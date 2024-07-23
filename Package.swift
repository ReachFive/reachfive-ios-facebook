// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reach5Facebook",
    products: [
        .library(name: "Reach5Facebook", targets: ["Reach5Facebook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ReachFive/reachfive-ios.git", branch: "7.0.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", .upToNextMajor(from: "17.0.0")),
    ],
    targets: [
        .target(
            name: "Reach5Facebook",
            dependencies: [
                .product(name: "Reach5", package: "reachfive-ios"),
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FacebookLogin", package: "facebook-ios-sdk"),
            ],
            path: "IdentitySdkFacebook"),
    ]
)
