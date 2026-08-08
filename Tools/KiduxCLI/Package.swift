// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KiduxCLI",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "kidux", targets: ["kidux"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "kidux",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
