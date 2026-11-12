import GameCore

/// Một hành động đã ghi lại cùng màu của người thực hiện.
public struct RecordedAction: Equatable, Sendable {
    public let color: PlayerColor
    public let action: GameAction

    public init(color: PlayerColor, action: GameAction) {
        self.color = color
        self.action = action
    }
}

/// Nhật ký toàn bộ hành động của một ván, mỗi hành động một byte:
///   1...6    đổ một xúc xắc ra giá trị đó (người thực hiện là người đang tới lượt)
///   16...31  đi quân: 16 + số quân (0...3) + 4 × cách dùng xúc xắc (0 viên thứ nhất, 1 viên thứ hai, 2 cộng điểm, 3 bay)
///   32...35  người chơi màu 0...3 bỏ cuộc (có thể xảy ra ngoài lượt)
///   64...99  đổ hai xúc xắc: 64 + (viên thứ nhất − 1) × 6 + (viên thứ hai − 1)
/// Định dạng này là một phần của dữ liệu trận nên phải ổn định giữa các phiên bản.
public struct ActionLog: Equatable, Sendable {
    public private(set) var bytes: [UInt8]

    public init(bytes: [UInt8] = []) {
        self.bytes = bytes
    }

    public var count: Int { bytes.count }

    public mutating func append(_ action: GameAction, by color: PlayerColor) {
        switch action {
        case .roll(let value, let second):
            if let second {
                bytes.append(UInt8(clamping: 64 + (value - 1) * 6 + (second - 1)))
            } else {
                bytes.append(UInt8(clamping: value))
            }
        case .move(let horse, let use):
            let code: Int = switch use {
            case .die(let index): index == 0 ? 0 : 1
            case .sum: 2
            case .fly: 3
            }
            bytes.append(UInt8(16 + horse.index + 4 * code))
        case .resign: bytes.append(UInt8(32 + color.rawValue))
        }
    }

    /// `other` có giữ nguyên toàn bộ lịch sử của nhật ký này không (chỉ được phép nối thêm).
    public func isPrefix(of other: ActionLog) -> Bool {
        other.bytes.count >= bytes.count && other.bytes.prefix(bytes.count).elementsEqual(bytes)
    }

    /// Phát lại nhật ký từ đầu bằng `GameEngine`. Mọi hành động đều đi qua kiểm tra luật như khi chơi thật;
    /// gặp hành động sai thì dừng và báo vị trí của nó.
    public func replay(colors: [PlayerColor], rules: RulesConfiguration) throws -> (engine: GameEngine, actions: [RecordedAction]) {
        var engine = GameEngine(colors: colors, rules: rules)
        var actions: [RecordedAction] = []
        actions.reserveCapacity(bytes.count)
        for (index, byte) in bytes.enumerated() {
            let recorded: RecordedAction
            switch byte {
            case 1...6:
                recorded = RecordedAction(color: engine.state.currentColor, action: .roll(value: Int(byte)))
            case 16...31:
                let color = engine.state.currentColor
                let code = (Int(byte) - 16) / 4
                let use: DiceUse = switch code {
                case 0: .die(index: 0)
                case 1: .die(index: 1)
                case 2: .sum
                default: .fly
                }
                recorded = RecordedAction(color: color, action: .move(horse: HorseID(color, (Int(byte) - 16) % 4), use: use))
            case 64...99:
                let pair = Int(byte) - 64
                recorded = RecordedAction(color: engine.state.currentColor, action: .roll(value: pair / 6 + 1, second: pair % 6 + 1))
            case 32...35:
                guard let color = PlayerColor(rawValue: Int(byte) - 32) else { throw OnlineMatchError.illegalAction(index: index) }
                recorded = RecordedAction(color: color, action: .resign)
            default:
                throw OnlineMatchError.illegalAction(index: index)
            }
            do {
                try engine.apply(recorded.action, by: recorded.color)
            } catch {
                throw OnlineMatchError.illegalAction(index: index)
            }
            actions.append(recorded)
        }
        return (engine, actions)
    }
}
