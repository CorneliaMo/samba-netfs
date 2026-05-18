// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SambaNetFS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "mount-samba", targets: ["MountSamba"]),
        .library(name: "MountSambaCore", targets: ["MountSambaCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "CNetFS",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation", .when(platforms: [.macOS])),
                .linkedFramework("NetFS", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "MountSambaCore",
            dependencies: ["CNetFS"],
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "MountSamba",
            dependencies: [
                "MountSambaCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MountSambaTests",
            dependencies: ["MountSambaCore"]
        )
    ]
)
