// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SplitBillRelay",
    platforms: [
        .iOS(.v18), .macOS(.v15) // macOS so `swift test` runs hermetically on the Mac
    ],
    products: [
        .library(name: "SplitBillRelay", targets: ["SplitBillRelay"])
    ],
    dependencies: [
        .package(path: "../SplitBillCore")
    ],
    targets: [
        .target(name: "SplitBillRelay", dependencies: ["SplitBillCore"]),
        .testTarget(name: "SplitBillRelayTests", dependencies: ["SplitBillRelay"])
    ],
    swiftLanguageModes: [.v6]
)
