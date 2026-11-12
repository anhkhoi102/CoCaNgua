/// Ô an toàn: quân đứng trên ô an toàn không thể bị đá; nhiều màu được đứng chung.
public enum SafeSquareRule: String, Codable, CaseIterable, Sendable {
    /// Không có ô an toàn (luật truyền thống).
    case none
    /// Bốn ô xuất phát là ô an toàn.
    case startSquares
    /// Bốn ô xuất phát và bốn ô giữa mỗi cạnh (kiểu Ludo hiện đại).
    case startAndMidSquares
}

/// Cách quân vào và leo cột về đích.
public enum HomeEntryRule: String, Codable, CaseIterable, Sendable {
    /// Truyền thống: quân phải dừng đúng ô cửa chuồng. Từ cửa chuồng, đổ được số nào thì nhảy lên
    /// bậc đó (các bậc phía dưới phải trống). Trong cột, lên bậc k+1 phải đổ đúng số k+1.
    case exactRungDirect
    /// Truyền thống, biến thể chặt: từ cửa chuồng phải đổ 1 để lên bậc 1, rồi 2 lên bậc 2, ... tới 6.
    case exactRungStepwise
    /// Kiểu Ludo: đi tiếp theo số chấm xúc xắc vào thẳng cột đích, không được đi quá bậc 6.
    case pipCount
}

/// Toàn bộ biến thể luật được hỗ trợ. Mọi chế độ chơi (đấu máy, chơi mạng) dùng chung cấu trúc này;
/// không có nơi nào khác trong mã nguồn tự quyết định luật.
public struct RulesConfiguration: Codable, Equatable, Sendable {
    /// Giá trị xúc xắc cho phép ra quân.
    public var releaseValues: Set<Int>
    /// Giá trị xúc xắc được đổ thêm lượt.
    public var bonusTurnValues: Set<Int>
    /// Giới hạn số lần đổ được thưởng liên tiếp. Khi lần đổ thưởng thứ `n` xảy ra, lần đổ đó bị huỷ
    /// và mất lượt. `nil` = không giới hạn.
    public var maxConsecutiveBonusRolls: Int?
    /// Cản đường: quân không được nhảy qua quân khác (bất kể màu nào).
    public var blocking: Bool
    /// Cho phép nhiều quân cùng màu đứng chung một ô trên đường chạy. Khi bật, một ô có từ hai quân
    /// cùng màu trở lên không thể bị đá.
    public var allowStacking: Bool
    public var safeSquares: SafeSquareRule
    public var homeEntry: HomeEntryRule
    /// Số xúc xắc đổ mỗi lần: 1 (thường) hoặc 2 (chế độ nhanh). Với hai viên, người chơi dùng riêng từng viên
    /// hoặc cộng lại cho một quân, và chỉ được đổ thêm khi ra đôi.
    public var diceCount: Int
    /// Một viên ra 1 cho phép quân trên đường chạy bay tới ô cửa chuồng kế tiếp phía trước.
    public var flyOnOne: Bool

    public init(releaseValues: Set<Int>, bonusTurnValues: Set<Int>, maxConsecutiveBonusRolls: Int?,
                blocking: Bool, allowStacking: Bool, safeSquares: SafeSquareRule, homeEntry: HomeEntryRule,
                diceCount: Int = 1, flyOnOne: Bool = true) {
        self.releaseValues = releaseValues
        self.bonusTurnValues = bonusTurnValues
        self.maxConsecutiveBonusRolls = maxConsecutiveBonusRolls
        self.blocking = blocking
        self.allowStacking = allowStacking
        self.safeSquares = safeSquares
        self.homeEntry = homeEntry
        self.diceCount = diceCount
        self.flyOnOne = flyOnOne
    }

    /// Luật Cờ Cá Ngựa truyền thống.
    public static let traditional = RulesConfiguration(
        releaseValues: [6], bonusTurnValues: [6], maxConsecutiveBonusRolls: nil,
        blocking: true, allowStacking: false, safeSquares: .none, homeEntry: .exactRungDirect)

    /// Biến thể hiện đại kiểu Ludo: có ô an toàn, được chồng quân, ba lần 6 mất lượt (vẫn cản đường).
    public static let modern = RulesConfiguration(
        releaseValues: [6], bonusTurnValues: [6], maxConsecutiveBonusRolls: 3,
        blocking: true, allowStacking: true, safeSquares: .startAndMidSquares, homeEntry: .pipCount)

    public func isValid() -> Bool {
        let dice = Set(GameRules.diceRange)
        return !releaseValues.isEmpty && releaseValues.isSubset(of: dice) && bonusTurnValues.isSubset(of: dice)
            && (maxConsecutiveBonusRolls.map { $0 >= 2 } ?? true)
            && (1...GameRules.maxDice).contains(diceCount)
    }
}

public enum GameRules {
    public static let diceRange = 1...6
    public static let maxDice = 2
    public static let minPlayers = 2
    public static let maxPlayers = PlayerColor.allCases.count

    /// Màu mặc định theo số người: 2 người ngồi đối diện nhau.
    public static func defaultColors(playerCount: Int) -> [PlayerColor] {
        switch playerCount {
        case 2: return [.red, .green]
        case 3: return [.red, .blue, .green]
        default: return PlayerColor.allCases
        }
    }
}
