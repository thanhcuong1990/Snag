// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Snag",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "Snag", targets: ["Snag"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Snag",
            dependencies: ["SnagObjC"],
            path: "ios/Snag"
        ),
        .target(
            name: "SnagObjC",
            dependencies: [],
            path: "ios/SnagObjC",
            publicHeadersPath: "include"
        )
    ]
)
