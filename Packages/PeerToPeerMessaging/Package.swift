/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The package file for the PeerToPeerMessaging package.
*/
// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PeerToPeerMessaging",
    platforms: [
        .visionOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PeerToPeerMessaging",
            targets: ["PeerToPeerMessaging"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PeerToPeerMessaging",
            dependencies: [.product(name: "X509", package: "swift-certificates")],

        )

    ]
)
