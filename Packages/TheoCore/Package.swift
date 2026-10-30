// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheoCore",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "TheoCore", targets: ["TheoCore"])
    ],
    targets: [
        .target(name: "TheoCore"),
        .testTarget(name: "TheoCoreTests", dependencies: ["TheoCore"])
    ],
    swiftLanguageModes: [.v5]
)
