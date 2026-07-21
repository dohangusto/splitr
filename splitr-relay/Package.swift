// swift-tools-version: 6.1
import PackageDescription

// Standalone relay server — the one sanctioned "server we manage". It is a
// dumb mailbox: stores and forwards bytes keyed by session token, never runs
// bill math, claim resolution, or CloudKit. Deliberately a separate package
// (its own folder/repo), NOT linked into any iOS app target.
//
// It reuses `SplitBillRelay`'s DTOs by path so the wire contract has a single
// source of truth and cannot drift from the client. That path dependency is a
// build-time reuse only; it does not put the server inside the app targets.
let package = Package(
    name: "splitr-relay",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        .package(path: "../Packages/SplitBillRelay"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SplitBillRelay", package: "SplitBillRelay"),
            ],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        )
    ],
    swiftLanguageModes: [.v6]
)
