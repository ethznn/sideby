// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sideby",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SidebyCore",
            targets: ["SidebyCore"]
        ),
        .library(
            name: "SidebySystem",
            targets: ["SidebySystem"]
        ),
        .library(
            name: "SidebyUI",
            targets: ["SidebyUI"]
        ),
        .executable(
            name: "SidebyDevApp",
            targets: ["SidebyDevApp"]
        ),
        .executable(
            name: "SidebyApp",
            targets: ["SidebyApp"]
        )
    ],
    targets: [
        .target(
            name: "SidebyCore"
        ),
        .target(
            name: "SidebySystem",
            dependencies: ["SidebyCore"]
        ),
        .target(
            name: "SidebyUI",
            dependencies: [
                "SidebyCore",
                "SidebySystem"
            ]
        ),
        .executableTarget(
            name: "SidebyDevApp",
            dependencies: [
                "SidebyCore",
                "SidebySystem",
                "SidebyUI"
            ]
        ),
        .executableTarget(
            name: "SidebyApp",
            dependencies: [
                "SidebyCore",
                "SidebySystem",
                "SidebyUI"
            ]
        ),
        .testTarget(
            name: "SidebyCoreTests",
            dependencies: ["SidebyCore"]
        ),
        .testTarget(
            name: "SidebySystemTests",
            dependencies: [
                "SidebyCore",
                "SidebySystem"
            ]
        ),
        .testTarget(
            name: "SidebyUITests",
            dependencies: [
                "SidebyCore",
                "SidebySystem",
                "SidebyUI"
            ]
        )
    ]
)
