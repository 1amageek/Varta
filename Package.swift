// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Varta",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .executable(name: "vartad", targets: ["VartaDaemon"]),
        .library(name: "Varta", targets: ["Varta"]),
        .library(name: "VartaP2P", targets: ["VartaP2P"])
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/swift-peer-connectivity.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.91.0")
    ],
    targets: [
        .executableTarget(
            name: "VartaDaemon",
            dependencies: ["Varta"]
        ),
        .target(name: "Varta"),
        .target(
            name: "VartaP2P",
            dependencies: [
                "Varta",
                .product(name: "PeerConnectivity", package: "swift-peer-connectivity"),
                .product(name: "NIOCore", package: "swift-nio")
            ]
        ),
        .testTarget(
            name: "VartaTests",
            dependencies: ["Varta"]
        ),
        .testTarget(
            name: "VartaP2PTests",
            dependencies: [
                "VartaP2P",
                "Varta",
                .product(name: "PeerConnectivity", package: "swift-peer-connectivity"),
                .product(name: "NIOCore", package: "swift-nio")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
