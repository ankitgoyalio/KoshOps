// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KoshOps",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "koshops", targets: ["KoshOps"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.8.2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "KoshOps",
            dependencies: [
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ]
        ),
        .testTarget(
            name: "KoshOpsTests",
            dependencies: ["KoshOps"]
        ),
    ]
)
