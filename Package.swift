// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kolibrie",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ColibriKit", targets: ["ColibriKit"]),
        .library(name: "ColibriAPI", targets: ["ColibriAPI"]),
        .executable(name: "KolibrieApp", targets: ["KolibrieApp"]),
        .executable(name: "kolibrie", targets: ["kolibrie"]),
    ],
    targets: [
        .target(name: "ColibriKit"),
        .target(name: "ColibriAPI", dependencies: ["ColibriKit"]),
        .executableTarget(
            name: "KolibrieApp",
            dependencies: ["ColibriKit", "ColibriAPI"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "kolibrie", dependencies: ["ColibriKit", "ColibriAPI"]),
        .testTarget(
            name: "ColibriKitTests",
            dependencies: ["ColibriKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ColibriAPITests", dependencies: ["ColibriAPI"]),
    ]
)
