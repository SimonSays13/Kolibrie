// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftColibri",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ColibriKit", targets: ["ColibriKit"]),
        .library(name: "ColibriAPI", targets: ["ColibriAPI"]),
        .executable(name: "SwiftColibriApp", targets: ["SwiftColibriApp"]),
        .executable(name: "swiftcolibri", targets: ["swiftcolibri"]),
    ],
    targets: [
        .target(name: "ColibriKit"),
        .target(name: "ColibriAPI", dependencies: ["ColibriKit"]),
        .executableTarget(
            name: "SwiftColibriApp",
            dependencies: ["ColibriKit", "ColibriAPI"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "swiftcolibri", dependencies: ["ColibriKit", "ColibriAPI"]),
        .testTarget(
            name: "ColibriKitTests",
            dependencies: ["ColibriKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ColibriAPITests", dependencies: ["ColibriAPI"]),
    ]
)
