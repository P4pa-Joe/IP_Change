// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IPChange",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "IP Change",
            path: "Sources/IPChange"
        )
    ]
)
