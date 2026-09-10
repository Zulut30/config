// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuotaDashboard",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "CodexQuotaDashboard",
            targets: ["CodexQuotaDashboard"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CodexQuotaDashboard",
            path: "Sources/CodexQuotaDashboard"
        ),
    ]
)
