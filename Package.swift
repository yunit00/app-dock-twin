// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockTwin",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DockTwin", targets: ["DockTwin"])],
    targets: [.executableTarget(name: "DockTwin")],
    swiftLanguageModes: [.v5]
)
