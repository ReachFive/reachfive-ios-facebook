// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reach5Facebook",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Reach5Facebook", targets: ["Reach5Facebook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ReachFive/reachfive-ios.git", .upToNextMajor(from: "7.1.4")),//demander la 7.2
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", .upToNextMinor(from: "17.4.0")),
    ],
    targets: [
        .target(
            name: "Reach5Facebook",
            dependencies: [
                .product(name: "Reach5", package: "reachfive-ios"),
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FacebookLogin", package: "facebook-ios-sdk"),
            ],
            resources: [
              .copy("PrivacyInfo.xcprivacy")
            ]
        ),
    ]
)
