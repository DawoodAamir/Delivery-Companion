// swift-tools-version: 5.7
import PackageDescription
let package = Package(name: "DeliveryCore", platforms: [.iOS(.v15), .macOS(.v12)], products: [.library(name: "DeliveryCore", targets: ["DeliveryCore"])], targets: [.target(name: "DeliveryCore", path: "Sources/Core"), .testTarget(name: "DeliveryCoreTests", dependencies: ["DeliveryCore"], path: "Tests/Core")])
