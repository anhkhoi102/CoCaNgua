/// Bốn màu quân, theo thứ tự lượt quanh bàn cờ (trên màn hình là ngược chiều kim đồng hồ).
public enum PlayerColor: Int, CaseIterable, Codable, Hashable, Sendable {
    case red, blue, green, yellow
}

public enum PlayerStatus: String, Codable, Sendable {
    case active
    /// Bỏ cuộc hoặc rời trận (chơi mạng). Quân đã bị gỡ khỏi bàn, lượt bị bỏ qua.
    case resigned
}

/// Một người chơi trong ván: màu, bốn quân ngựa và trạng thái.
/// Tên hiển thị, người/máy... thuộc tầng trên, không nằm trong GameCore.
public struct Player: Codable, Equatable, Sendable {
    public let color: PlayerColor
    public var horses: [HorsePosition]
    public var status: PlayerStatus

    public init(color: PlayerColor,
                horses: [HorsePosition] = Array(repeating: .stable, count: Board.horsesPerPlayer),
                status: PlayerStatus = .active) {
        precondition(horses.count == Board.horsesPerPlayer)
        self.color = color
        self.horses = horses
        self.status = status
    }

    /// Số quân đang đứng trong cột về đích.
    public var horsesHome: Int { horses.filter { $0.isHome }.count }

    /// Đã thắng: cả bốn quân chiếm bốn bậc cao nhất (6, 5, 4, 3).
    public var hasWon: Bool {
        let rungs = Set(horses.compactMap { $0.homeRung })
        let top = Set((Board.homeRungs - Board.horsesPerPlayer + 1)...Board.homeRungs)
        return rungs == top
    }
}
