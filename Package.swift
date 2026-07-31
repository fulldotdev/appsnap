// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Appsnap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "appsnap", targets: ["Appsnap"]),
    ],
    targets: [
        .executableTarget(name: "Appsnap"),
    ]
)
