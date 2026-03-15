// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniAnalyse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniAnalyseCore", targets: ["MuniAnalyseCore"]),
        .library(name: "MuniAnalyseInterop", targets: ["MuniAnalyseInterop"]),
        .executable(name: "muni-analyse-cli", targets: ["MuniAnalyseCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
        .package(url: "https://github.com/Macthieu/OrchivisteKit.git", exact: "0.2.0")
    ],
    targets: [
        .target(name: "MuniAnalyseCore"),
        .target(
            name: "MuniAnalyseInterop",
            dependencies: [
                "MuniAnalyseCore",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "MuniAnalyseCLI",
            dependencies: [
                "MuniAnalyseInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "OrchivisteKitInterop", package: "OrchivisteKit")
            ]
        ),
        .testTarget(
            name: "MuniAnalyseTests",
            dependencies: [
                "MuniAnalyseCore",
                "MuniAnalyseInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
