// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessTV",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
        .executable(name: "ChessCoreValidation", targets: ["ChessCoreValidation"])
    ],
    targets: [
        .target(name: "ChessCore"),
        .executableTarget(name: "ChessCoreValidation", dependencies: ["ChessCore"], path: "Tools/ChessCoreValidation"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"])
    ]
)
