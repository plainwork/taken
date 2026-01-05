// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "taken",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "taken", targets: ["taken"])
    ],
    targets: [
        .executableTarget(
            name: "taken"
        )
    ]
)
