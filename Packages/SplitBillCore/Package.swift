// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SplitBillCore",
    products: [
        .library(name: "SplitBillCore", targets: ["SplitBillCore"])
    ],
    targets: [
        .target(name: "SplitBillCore"),
        .testTarget(name: "SplitBillCoreTests", dependencies: ["SplitBillCore"])
    ],
    swiftLanguageModes: [.v6]
)
