public enum GamePhase: Codable, Equatable, Sendable {
    /// Người chơi hiện tại cần đổ xúc xắc.
    case awaitingRoll
    /// Đã đổ, người chơi hiện tại cần chọn nước đi. `roll` là viên đầu tiên còn chưa dùng
    /// (xem `GameState.remainingDice` để biết đủ các viên ở chế độ hai xúc xắc).
    case awaitingMove(roll: Int)
    case finished(winner: PlayerColor)
}

/// Toàn bộ trạng thái một ván. Là kiểu giá trị thuần, Codable, dùng chung cho đấu máy và chơi mạng.
public struct GameState: Codable, Equatable, Sendable {
    /// Phiên bản định dạng trạng thái; tăng khi thay đổi không tương thích.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var rules: RulesConfiguration
    /// Người chơi theo thứ tự lượt.
    public var players: [Player]
    public var currentPlayerIndex: Int
    public var phase: GamePhase
    /// Viên đầu tiên của lần đổ gần nhất.
    public var lastRoll: Int?
    /// Các viên của lần đổ gần nhất, theo thứ tự đổ.
    public var rolledDice: [Int]
    /// Các viên của lần đổ đó còn chưa dùng.
    public var remainingDice: [Int]
    /// Số lần đổ được thưởng liên tiếp trong lượt hiện tại.
    public var consecutiveBonusRolls: Int
    /// Số lượt đã chuyển (bắt đầu từ 1).
    public var turnNumber: Int
    /// Số hành động đã áp dụng; dùng để phát hiện hành động trùng lặp hoặc lỗi thứ tự khi chơi mạng.
    public var actionCount: Int

    public init(colors: [PlayerColor], rules: RulesConfiguration = .traditional) {
        precondition((GameRules.minPlayers...GameRules.maxPlayers).contains(colors.count), "Cần 2–4 người chơi")
        precondition(Set(colors).count == colors.count, "Màu bị trùng")
        precondition(rules.isValid(), "Cấu hình luật không hợp lệ")
        self.schemaVersion = Self.currentSchemaVersion
        self.rules = rules
        self.players = colors.sorted { $0.rawValue < $1.rawValue }.map { Player(color: $0) }
        self.currentPlayerIndex = 0
        self.phase = .awaitingRoll
        self.lastRoll = nil
        self.rolledDice = []
        self.remainingDice = []
        self.consecutiveBonusRolls = 0
        self.turnNumber = 1
        self.actionCount = 0
    }

    public var currentPlayer: Player { players[currentPlayerIndex] }
    public var currentColor: PlayerColor { currentPlayer.color }

    public var winner: PlayerColor? {
        if case .finished(let winner) = phase { return winner }
        return nil
    }

    public var isFinished: Bool { winner != nil }

    public func playerIndex(of color: PlayerColor) -> Int? {
        players.firstIndex { $0.color == color }
    }

    public func player(_ color: PlayerColor) -> Player? {
        playerIndex(of: color).map { players[$0] }
    }

    public func position(of horse: HorseID) -> HorsePosition? {
        guard let player = player(horse.color), player.horses.indices.contains(horse.index) else { return nil }
        return player.horses[horse.index]
    }

    /// Mọi quân (bất kể màu) đang đứng trên ô `square` của đường chạy.
    public func horses(onTrack square: Int) -> [HorseID] {
        players.flatMap { player in
            player.horses.indices.compactMap { index in
                player.horses[index] == .track(square) ? HorseID(player.color, index) : nil
            }
        }
    }

    public func isRungOccupied(_ rung: Int, color: PlayerColor) -> Bool {
        player(color)?.horses.contains(.home(rung)) ?? false
    }

    /// Điểm tiến độ của một người chơi, dùng để xếp hạng những người chưa về đích khi ván kết thúc.
    public func progressScore(of color: PlayerColor) -> Int {
        guard let player = player(color) else { return 0 }
        return player.horses.reduce(0) { total, position in
            switch position {
            case .stable: return total
            case .track(let square): return total + 1 + (Board.progress(ofSquare: square, for: color) ?? 0)
            case .home(let rung): return total + 1 + Board.stepsToMouth + rung
            }
        }
    }

    /// Bảng xếp hạng: người thắng, rồi theo tiến độ giảm dần; người bỏ cuộc xếp cuối.
    public func standings() -> [PlayerColor] {
        players.sorted { a, b in
            if (a.color == winner) != (b.color == winner) { return a.color == winner }
            if (a.status == .active) != (b.status == .active) { return a.status == .active }
            let (sa, sb) = (progressScore(of: a.color), progressScore(of: b.color))
            return sa != sb ? sa > sb : a.color.rawValue < b.color.rawValue
        }.map(\.color)
    }
}
