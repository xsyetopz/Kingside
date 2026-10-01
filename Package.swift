// swift-tools-version: 6.2
import PackageDescription

// Layering rules for the targets are in `Tools/import-rules.json` and checked by
// `Tools/check-imports.sh`.
let package = Package(
  name: "Kingside",
  defaultLocalization: "en-US",
  // The floor is set by Observation and CKSyncEngine (iOS 17, tvOS 17, macOS 14).
  platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "ChessCore", targets: ["ChessCore"]),
    .library(name: "ChessContent", targets: ["ChessContent"]),
    .library(name: "ChessComLink", targets: ["ChessComLink"]),
    .library(name: "LichessLink", targets: ["LichessLink"]),
    .library(name: "ChessOnline", targets: ["ChessOnline"]),
    .library(name: "ChessPlay", targets: ["ChessPlay"]),
    .library(name: "ChessBoardScene", targets: ["ChessBoardScene"]),
    .library(name: "ChessFeedback", targets: ["ChessFeedback"]),
    .library(name: "ChessUI", targets: ["ChessUI"]),
    .executable(name: "ChessBench", targets: ["ChessBench"]),
  ],
  targets: [
    .target(name: "ChessCore"),
    .target(name: "ChessContent", dependencies: ["ChessCore"], resources: [.process("Resources")]),
    .target(name: "ChessComLink", dependencies: ["ChessCore"]),
    .target(name: "LichessLink", dependencies: ["ChessCore"]),
    .target(name: "ChessOnline"),
    .target(name: "ChessPlay", dependencies: ["ChessCore", "ChessContent"]),
    .target(name: "ChessBoardScene", dependencies: ["ChessCore", "ChessContent", "ChessPlay"]),
    .target(name: "ChessFeedback", dependencies: ["ChessCore", "ChessContent", "ChessPlay"]),
    .target(
      name: "ChessUI",
      dependencies: [
        "ChessCore", "ChessContent", "ChessPlay", "ChessBoardScene", "ChessFeedback",
        "ChessComLink", "LichessLink", "ChessOnline",
      ]
    ),
    .executableTarget(name: "ChessBench", dependencies: ["ChessCore"], path: "Tools/ChessBench"),
    .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    .testTarget(name: "ChessContentTests", dependencies: ["ChessContent"]),
    .testTarget(
      name: "ChessComLinkTests",
      dependencies: ["ChessComLink", "ChessCore"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "LichessLinkTests",
      dependencies: ["LichessLink", "ChessCore"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "ChessOnlineTests", dependencies: ["ChessOnline"]),
    .testTarget(
      name: "ChessPlayTests",
      dependencies: ["ChessPlay", "ChessCore", "ChessContent"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "ChessBoardSceneTests",
      dependencies: ["ChessBoardScene", "ChessPlay", "ChessCore", "ChessContent"]
    ),
    .testTarget(
      name: "ChessFeedbackTests",
      dependencies: ["ChessFeedback", "ChessPlay", "ChessCore", "ChessContent"]
    ),
    .testTarget(
      name: "ChessUITests",
      dependencies: [
        "ChessUI", "ChessPlay", "ChessCore", "ChessContent", "ChessComLink", "LichessLink",
        "ChessOnline",
      ]
    ),
  ]
)
