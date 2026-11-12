import GameCore

/// Mã phòng 6 chữ số để bạn bè vào cùng một phòng mà không cần máy chủ riêng.
///
/// Mã được dùng làm `playerGroup` khi ghép trận qua Game Center: Game Center chỉ ghép những người gửi cùng một
/// `playerGroup` với nhau. Chữ số đầu là số người chơi (2–4) để người vào phòng gửi yêu cầu ghép trận giống hệt
/// người tạo; năm chữ số sau là ngẫu nhiên.
public struct RoomCode: Equatable, Sendable {
    public static let length = 6

    public let playerCount: Int
    /// Giá trị gửi cho Game Center làm nhóm ghép trận.
    public let group: Int

    /// Mã để hiển thị và đọc cho bạn bè.
    public var text: String { String(group) }

    public static func generate(playerCount: Int, using generator: inout some RandomNumberGenerator) -> RoomCode {
        let count = min(max(playerCount, GameRules.minPlayers), GameRules.maxPlayers)
        return RoomCode(playerCount: count, group: count * 100_000 + Int.random(in: 0..<100_000, using: &generator))
    }

    /// Đọc mã người chơi nhập (bỏ qua khoảng trắng và dấu gạch). `nil` nếu không phải mã hợp lệ.
    public init?(_ text: String) {
        let digits = text.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == Self.length, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let group = Int(digits),
              (GameRules.minPlayers...GameRules.maxPlayers).contains(group / 100_000) else { return nil }
        self.init(playerCount: group / 100_000, group: group)
    }

    private init(playerCount: Int, group: Int) {
        self.playerCount = playerCount
        self.group = group
    }
}
