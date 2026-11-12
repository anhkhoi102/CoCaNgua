import Foundation
import GameCore

public enum OnlineMatchError: Error, Equatable, Sendable {
    /// Dữ liệu không đọc được.
    case corrupt
    /// Trận được tạo bởi bản ứng dụng mới hơn; cần cập nhật để chơi tiếp.
    case newerFormat(Int)
    /// Số chỗ ngồi hoặc màu không khớp với trận.
    case invalidSeats
    /// Luật trong dữ liệu trận không hợp lệ.
    case invalidRules
    /// Hành động thứ `index` trong nhật ký vi phạm luật hoặc sai lượt.
    case illegalAction(index: Int)
    /// Dữ liệu mới không giữ nguyên lịch sử đã biết (có người sửa hoặc xoá hành động cũ).
    case historyRewritten
    /// Người đang giữ lượt theo Game Center không phải người tới lượt theo ván cờ.
    case turnMismatch
    case tooLarge
}

/// Dữ liệu của một trận chơi mạng, lưu trong `matchData` của Game Center.
///
/// Chỉ chứa những gì cần để mọi máy dựng lại đúng một ván: luật, màu của từng chỗ ngồi và nhật ký hành động.
/// Trạng thái ván không được gửi đi; mỗi máy tự phát lại nhật ký bằng `GameEngine`, nên một trạng thái "bịa"
/// không thể được chấp nhận.
public struct OnlineMatchData: Codable, Equatable, Sendable {
    /// 2: thêm chế độ hai xúc xắc và nước bay (luật và mã hành động mới).
    public static let currentFormat = 4

    public var format: Int
    public var rules: RulesConfiguration
    /// Màu của từng người tham gia, theo thứ tự `participants` của Game Center.
    public var seatColors: [PlayerColor]
    public var log: Data

    public init(playerCount: Int, rules: RulesConfiguration) {
        self.format = Self.currentFormat
        self.rules = rules
        self.seatColors = GameRules.defaultColors(playerCount: playerCount)
        self.log = Data()
    }

    public var actionLog: ActionLog {
        get { ActionLog(bytes: Array(log)) }
        set { log = Data(newValue.bytes) }
    }

    public func encoded(maximumSize: Int? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        if let maximumSize, data.count > maximumSize { throw OnlineMatchError.tooLarge }
        return data
    }
}

/// Một trận đã được đọc và kiểm tra: dữ liệu gốc, ván cờ dựng lại từ nhật ký, và danh sách hành động.
public struct OnlineMatchSnapshot: Sendable {
    public let data: OnlineMatchData
    public let engine: GameEngine
    public let actions: [RecordedAction]

    public var state: GameState { engine.state }
    public var log: ActionLog { data.actionLog }

    /// Chỗ ngồi (chỉ số người tham gia) của một màu.
    public func seat(of color: PlayerColor) -> Int? { data.seatColors.firstIndex(of: color) }

    /// Chỗ ngồi của người đang tới lượt trong ván cờ, hoặc `nil` nếu ván đã kết thúc.
    public var seatToMove: Int? { state.isFinished ? nil : seat(of: state.currentColor) }
}

public enum OnlineMatchValidator {
    /// Đọc dữ liệu trận nhận từ Game Center. Dữ liệu rỗng nghĩa là trận mới chưa ai đi: dùng `newMatchRules`.
    public static func load(_ raw: Data?, playerCount: Int, newMatchRules: RulesConfiguration) throws -> OnlineMatchSnapshot {
        guard let raw, !raw.isEmpty else {
            guard (GameRules.minPlayers...GameRules.maxPlayers).contains(playerCount) else { throw OnlineMatchError.invalidSeats }
            return try snapshot(OnlineMatchData(playerCount: playerCount, rules: newMatchRules))
        }
        struct Header: Decodable { let format: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: raw) else { throw OnlineMatchError.corrupt }
        guard header.format <= OnlineMatchData.currentFormat else { throw OnlineMatchError.newerFormat(header.format) }
        guard header.format == OnlineMatchData.currentFormat, let data = try? JSONDecoder().decode(OnlineMatchData.self, from: raw) else { throw OnlineMatchError.corrupt }
        guard data.seatColors.count == playerCount, Set(data.seatColors).count == playerCount,
              (GameRules.minPlayers...GameRules.maxPlayers).contains(playerCount) else { throw OnlineMatchError.invalidSeats }
        return try snapshot(data)
    }

    /// Dựng lại ván từ dữ liệu trận đã giải mã (kiểm tra luật và phát lại toàn bộ nhật ký).
    public static func snapshot(_ data: OnlineMatchData) throws -> OnlineMatchSnapshot {
        guard data.rules.isValid() else { throw OnlineMatchError.invalidRules }
        let replayed = try data.actionLog.replay(colors: data.seatColors, rules: data.rules)
        return OnlineMatchSnapshot(data: data, engine: replayed.engine, actions: replayed.actions)
    }

    /// Kiểm tra một bản cập nhật so với những gì máy này đã biết.
    /// - `known`: nhật ký lần gần nhất máy này thấy của trận này (nếu có). Bản mới phải giữ nguyên nó.
    /// - `currentSeat`: chỗ ngồi đang giữ lượt theo Game Center. Phải trùng người tới lượt trong ván.
    /// - `outOfPlaySeats`: các chỗ ngồi Game Center báo đã rời trận; người tới lượt trong ván được phép là một
    ///   trong số đó (họ sẽ được xử bỏ cuộc ở bước `reconciliation`).
    public static func validate(_ incoming: OnlineMatchSnapshot, known: ActionLog?, currentSeat: Int?, outOfPlaySeats: Set<Int> = []) throws {
        if let known, !known.isPrefix(of: incoming.log) { throw OnlineMatchError.historyRewritten }
        guard let currentSeat, let seatToMove = incoming.seatToMove else { return }
        if seatToMove != currentSeat && !outOfPlaySeats.contains(seatToMove) { throw OnlineMatchError.turnMismatch }
    }

    /// Các hành động bỏ cuộc cần thêm vào ván cho những người Game Center báo đã rời trận (thoát, hết hạn lượt)
    /// mà trong ván vẫn còn đang chơi.
    public static func reconciliation(outOfPlaySeats: Set<Int>, in snapshot: OnlineMatchSnapshot) -> [RecordedAction] {
        guard !snapshot.state.isFinished else { return [] }
        return outOfPlaySeats.sorted().compactMap { seat in
            guard snapshot.data.seatColors.indices.contains(seat) else { return nil }
            let color = snapshot.data.seatColors[seat]
            guard snapshot.state.player(color)?.status == .active else { return nil }
            return RecordedAction(color: color, action: .resign)
        }
    }
}
