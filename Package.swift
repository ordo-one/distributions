// swift-tools-version:6.1
import PackageDescription

let package: Package = .init(
    name: "distributions",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .library(name: "Distributions", targets: ["Distributions"]),
        .library(name: "Random", targets: ["Random"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.3"),
        .package(url: "https://github.com/ordo-one/dollup", from: "1.0.1"),
        .package(url: "https://github.com/ordo-one/lexic", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "Distributions",
            dependencies: [
                .product(name: "Assert", package: "lexic"),
                .target(name: "Random"),
            ],
        ),
        .target(
            name: "Random",
            dependencies: [
                .product(name: "RealModule", package: "swift-numerics")
            ],
            linkerSettings: [
                .linkedLibrary("m")
            ],
        ),

        .testTarget(
            name: "RandomTests",
            dependencies: [
                .target(name: "Random")
            ],
        ),
    ]
)

for target: Target in package.targets {
    {
        $0 = ($0 ?? []) + [
            .enableUpcomingFeature("ExistentialAny")
        ]
    }(&target.swiftSettings)
}
