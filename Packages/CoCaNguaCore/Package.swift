// swift-tools-version: 6.0
//
// CoCaNguaCore: luật chơi Cờ Cá Ngựa thuần Swift. Không SpriteKit, GameKit, SwiftUI hay AppKit.
//
//   GameCore   bàn cờ, trạng thái ván, luật, kiểm tra nước đi, lượt chơi, AI
//   OnlineCore dữ liệu trận chơi mạng: mã hoá, phát lại và kiểm tra hợp lệ (không phụ thuộc GameKit)
//
// Chạy test từ dòng lệnh:  swift test --package-path Packages/CoCaNguaCore

import PackageDescription

let package = Package(
    name: "CoCaNguaCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "OnlineCore", targets: ["OnlineCore"])
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "OnlineCore", dependencies: ["GameCore"]),
        .testTarget(name: "GameRulesTests", dependencies: ["GameCore"]),
        .testTarget(name: "MoveValidationTests", dependencies: ["GameCore"]),
        .testTarget(name: "AITests", dependencies: ["GameCore"]),
        .testTarget(name: "MultiplayerStateTests", dependencies: ["GameCore", "OnlineCore"]),
    ]
)
