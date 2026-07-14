// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SplitBillSync",
    platforms: [
        .iOS(.v18), .macOS(.v15) // macOS so `swift test` runs hermetically on the Mac
    ],
    products: [
        .library(name: "SplitBillSync", targets: ["SplitBillSync"])
    ],
    dependencies: [
        .package(path: "../SplitBillCore")
    ],
    targets: [
        .target(name: "SplitBillSync", dependencies: ["SplitBillCore"]),
        .testTarget(name: "SplitBillSyncTests", dependencies: ["SplitBillSync"])
    ],
    swiftLanguageModes: [.v6]
)
