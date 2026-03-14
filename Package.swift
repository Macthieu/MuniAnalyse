// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniAnalyse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniAnalyseCore", targets: ["MuniAnalyseCore"]),
        .executable(name: "muni-analyse-cli", targets: ["MuniAnalyseCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "MuniAnalyseCore"),
        .executableTarget(name: "MuniAnalyseCLI", dependencies: ["MuniAnalyseCore"]),
        .testTarget(
            name: "MuniAnalyseTests",
            dependencies: [
                "MuniAnalyseCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
