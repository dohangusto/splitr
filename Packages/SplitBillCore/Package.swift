// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SplitBillCore",
    platforms: [
        .iOS(.v18), .macOS(.v15) // matches SplitBillSync; regex literals need modern floors
    ],
    products: [
        .library(name: "SplitBillCore", targets: ["SplitBillCore"])
    ],
    targets: [
        .target(name: "SplitBillCore"),
        .testTarget(name: "SplitBillCoreTests", dependencies: ["SplitBillCore"])
    ],
    swiftLanguageModes: [.v6]
)
