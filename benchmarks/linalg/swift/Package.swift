// swift-tools-version:5.9
// Build: swift build -c release
// MLX backend requires Apple Silicon and the mlx-swift package.

import PackageDescription

let package = Package(
    name: "matmul",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "matmul",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
            ],
            path: ".",
            sources: ["matmul.swift"]
        ),
    ]
)
