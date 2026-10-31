// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TouchpadCore", platforms: [.macOS(.v13), .iOS(.v16)], products: [.library(name: "TouchpadCore", targets: ["TouchpadCore"])], targets: [.target(name: "TouchpadCore", path: "Shared"), .testTarget(name: "TouchpadCoreTests", dependencies: ["TouchpadCore"], path: "Tests")])
