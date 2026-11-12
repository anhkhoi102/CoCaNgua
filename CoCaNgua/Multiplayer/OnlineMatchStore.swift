import Foundation
import OnlineCore

/// Ghi nhớ nhật ký gần nhất máy này đã thấy của từng trận, để phát hiện dữ liệu trận bị sửa lịch sử
/// kể cả sau khi mở lại ứng dụng.
@MainActor
struct OnlineMatchStore {
    private let defaults: UserDefaults
    private static let prefix = "online.knownLog."
    private static let roomPrefix = "online.roomCode."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func knownLog(for matchID: String) -> ActionLog? {
        defaults.data(forKey: Self.prefix + matchID).map { ActionLog(bytes: Array($0)) }
    }

    func remember(_ log: ActionLog, for matchID: String) {
        defaults.set(Data(log.bytes), forKey: Self.prefix + matchID)
    }

    /// Mã phòng của trận (nếu trận được tạo hoặc vào bằng mã), để hiện lại cho người chơi đọc cho bạn bè.
    func roomCode(for matchID: String) -> String? {
        defaults.string(forKey: Self.roomPrefix + matchID)
    }

    func remember(roomCode: String, for matchID: String) {
        defaults.set(roomCode, forKey: Self.roomPrefix + matchID)
    }

    func forget(_ matchID: String) {
        defaults.removeObject(forKey: Self.roomPrefix + matchID)
        defaults.removeObject(forKey: Self.prefix + matchID)
    }
}
