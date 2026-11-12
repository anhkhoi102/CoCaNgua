import Foundation
import GameCore

/// Một chỗ ngồi trong phòng chơi trực tiếp.
public struct RoomSeat: Codable, Equatable, Sendable {
    public var color: PlayerColor
    /// Định danh người chơi (Game Center) ngồi ở chỗ này; `nil` nghĩa là bot do máy của chủ phòng điều khiển.
    public var playerID: String?
    public var name: String

    public init(color: PlayerColor, playerID: String?, name: String) {
        self.color = color
        self.playerID = playerID
        self.name = name
    }

    public var isBot: Bool { playerID == nil }
}

/// Kế hoạch ván do chủ phòng chốt khi bấm Bắt đầu và gửi cho mọi người: luật, ai ngồi màu nào, chỗ nào là bot.
public struct RoomPlan: Codable, Equatable, Sendable {
    public var rules: RulesConfiguration
    public var hostID: String
    public var seats: [RoomSeat]

    /// Một người trong phòng trước khi bắt đầu.
    public struct Member: Equatable, Sendable {
        public var playerID: String
        public var name: String
        public init(playerID: String, name: String) {
            self.playerID = playerID
            self.name = name
        }
    }

    /// Xếp chỗ: chủ phòng trước, rồi những người đã vào (theo thứ tự định danh để mọi máy ra cùng kết quả),
    /// các chỗ còn trống cho bot. Phòng luôn đủ `seatCount` chỗ (2–4).
    public static func make(host: Member, guests: [Member], seatCount: Int, rules: RulesConfiguration, botName: (Int) -> String) -> RoomPlan {
        let count = min(max(seatCount, GameRules.minPlayers), GameRules.maxPlayers)
        let colors = GameRules.defaultColors(playerCount: count)
        let people = [host] + guests.sorted { $0.playerID < $1.playerID }.prefix(count - 1)
        var bots = 0
        let seats = colors.enumerated().map { index, color -> RoomSeat in
            if index < people.count { return RoomSeat(color: color, playerID: people[index].playerID, name: people[index].name) }
            bots += 1
            return RoomSeat(color: color, playerID: nil, name: botName(bots))
        }
        return RoomPlan(rules: rules, hostID: host.playerID, seats: seats)
    }

    public var colors: [PlayerColor] { seats.map(\.color) }

    public func seat(of playerID: String) -> RoomSeat? { seats.first { $0.playerID == playerID } }

    /// Kế hoạch có dùng được không: luật hợp lệ, số chỗ và màu đúng, chủ phòng có ngồi trong ván.
    public var isValid: Bool {
        rules.isValid() && (GameRules.minPlayers...GameRules.maxPlayers).contains(seats.count)
            && Set(colors).count == seats.count && seat(of: hostID) != nil
            && Set(seats.compactMap(\.playerID)).count == seats.compactMap(\.playerID).count
    }

    /// `sender` có quyền gửi hành động cho màu `color` không. Mỗi người chỉ đi quân của mình; chủ phòng đi thêm cho bot
    /// và cho những người đã rời phòng (`departed`).
    public func mayAct(sender: String, for color: PlayerColor, departed: Set<String> = []) -> Bool {
        guard let seat = seats.first(where: { $0.color == color }) else { return false }
        if seat.playerID == sender { return true }
        guard sender == hostID else { return false }
        return seat.playerID.map(departed.contains) ?? true
    }
}

/// Tin nhắn giữa các máy trong một phòng chơi trực tiếp.
public enum RoomMessage: Codable, Equatable, Sendable {
    /// Gửi khi vừa kết nối: máy này có phải chủ phòng không.
    case hello(isHost: Bool)
    /// Chủ phòng bắt đầu ván.
    case start(RoomPlan)
    /// Các hành động mới, nối vào nhật ký từ vị trí `from` (mã hoá như `ActionLog`).
    case actions(from: Int, bytes: Data)

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) -> RoomMessage? { try? JSONDecoder().decode(RoomMessage.self, from: data) }
}
