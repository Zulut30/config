// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kopilka",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kopilka", targets: ["Kopilka"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "KopilkaCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Kopilka", dependencies: ["KopilkaCore"],
                          linkerSettings: [.linkedFramework("Carbon")])
    ]
)
