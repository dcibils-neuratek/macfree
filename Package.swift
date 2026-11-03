// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacFree",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MacFreeCore"),
        .executableTarget(name: "MacFree", dependencies: ["MacFreeCore"]),
        .testTarget(name: "MacFreeCoreTests", dependencies: ["MacFreeCore"]),
    ]
)
