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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
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
        .target(
            name: "SidebyDevSupport",
            dependencies: [
                "SidebyCore",
                "SidebySystem"
            ]
        ),
        .executableTarget(
            name: "SidebyDevApp",
            dependencies: [
                "SidebyCore",
                "SidebyDevSupport",
                "SidebySystem",
                "SidebyUI"
            ]
        ),
        .executableTarget(
            name: "SidebyApp",
            dependencies: [
                "SidebyCore",
                "SidebySystem",
                "SidebyUI",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
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
                "SidebyDevSupport",
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
        ),
        .testTarget(
            name: "SidebyAppTests",
            dependencies: [
                "SidebyApp",
                "SidebyCore",
                "SidebySystem"
            ]
        )
    ]
)
