// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PickleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PickleCore", targets: ["PickleCore"])
    ],
    targets: [
        .target(name: "PickleCore"),
        .testTarget(name: "PickleCoreTests", dependencies: ["PickleCore"])
    ]
)
