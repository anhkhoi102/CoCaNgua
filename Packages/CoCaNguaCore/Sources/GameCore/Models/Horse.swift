/// Định danh một quân ngựa: màu và số thứ tự 0...3.
public struct HorseID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let color: PlayerColor
    public let index: Int

    public init(_ color: PlayerColor, _ index: Int) {
        self.color = color
        self.index = index
    }

    public var description: String { "\(color)#\(index)" }
}

/// Vị trí của một quân ngựa.
public enum HorsePosition: Hashable, Sendable {
    /// Trong chuồng, chưa ra quân.
    case stable
    /// Trên đường chạy chung, chỉ số ô tuyệt đối 0..<Board.trackLength.
    case track(Int)
    /// Trong cột về đích của màu mình, bậc 1...Board.homeRungs.
    case home(Int)

    public var isStable: Bool { self == .stable }
    public var isHome: Bool { homeRung != nil }

    public var trackSquare: Int? {
        if case .track(let square) = self { return square }
        return nil
    }

    public var homeRung: Int? {
        if case .home(let rung) = self { return rung }
        return nil
    }
}

/// Mã hoá gọn thành một số nguyên: -1 = chuồng, 0...55 = đường chạy, 101...106 = bậc đích.
/// Định dạng này là một phần của dữ liệu trận đấu mạng nên phải ổn định giữa các phiên bản.
extension HorsePosition: Codable {
    private static let homeBase = 100

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        switch raw {
        case -1:
            self = .stable
        case 0..<Board.trackLength:
            self = .track(raw)
        case (Self.homeBase + 1)...(Self.homeBase + Board.homeRungs):
            self = .home(raw - Self.homeBase)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Vị trí quân không hợp lệ: \(raw)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .stable: try container.encode(-1)
        case .track(let square): try container.encode(square)
        case .home(let rung): try container.encode(Self.homeBase + rung)
        }
    }
}
