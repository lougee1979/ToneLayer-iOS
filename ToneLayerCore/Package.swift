// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ToneLayerCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ToneLayerCore", targets: ["ToneLayerCore"])
    ],
    targets: [
        .target(name: "ToneLayerCore")
    ]
)
