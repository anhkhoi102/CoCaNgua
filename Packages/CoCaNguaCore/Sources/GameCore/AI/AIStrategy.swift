import Foundation

/// Đánh giá một nước đi theo các yếu tố chiến thuật. Chỉ đọc trạng thái và dùng `MoveValidator`/`GameEngine`,
/// nên máy luôn chơi theo đúng luật đang áp dụng (cản đường, ô an toàn, chồng quân, cách lên đích...).
public struct MoveAssessment: Equatable, Sendable {
    public let move: Move
    /// Nước này kết thúc ván với phần thắng.
    public var wins = false
    /// Tổng tiến độ của các quân đối phương bị đá.
    public var captureValue = 0.0
    /// Số bước tiến trên đường chạy hoặc trong cột đích.
    public var advance = 0.0
    /// Bậc đích đạt được (0 nếu không lên đích).
    public var rungReached = 0
    public var reachesMouth = false
    public var landsOnSafeSquare = false
    /// Xác suất quân vừa đi bị đá trước khi tới lượt mình lần nữa.
    public var threatAfter = 0.0
    /// Xác suất quân đó bị đá nếu đứng yên.
    public var threatBefore = 0.0
    /// Giá trị của quân (càng đi xa càng đáng giữ).
    public var horseValueBefore = 0.0
    public var horseValueAfter = 0.0
    /// Xác suất mình đá được quân đối phương ở lượt kế tiếp nếu đi nước này (chỉ tính ở chế độ chính xác).
    public var captureChanceNext = 0.0
    /// Số quân mình đang ở trên đường chạy trước nước đi.
    public var ownHorsesOnTrack = 0
}

public enum AIStrategy {
    /// Phân tích mọi nước trong `moves`. `exactThreats` = tính chính xác các nước đá quân của đối phương
    /// (dùng cho mức Khó); khi tắt chỉ ước lượng theo khoảng cách.
    public static func assess(_ moves: [Move], in state: GameState, exactThreats: Bool) -> [MoveAssessment] {
        moves.map { assess($0, in: state, exactThreats: exactThreats) }
    }

    static func assess(_ move: Move, in state: GameState, exactThreats: Bool) -> MoveAssessment {
        let color = move.horse.color
        var assessment = MoveAssessment(move: move)
        var engine = GameEngine(state: state)
        _ = try? engine.apply(move.action, by: color)
        let after = engine.state

        assessment.wins = after.winner == color
        assessment.captureValue = move.captures.reduce(0) { $0 + value(of: state.position(of: $1) ?? .stable, color: $1.color) }
        assessment.rungReached = move.to.homeRung ?? 0
        assessment.horseValueBefore = value(of: move.from, color: color)
        assessment.horseValueAfter = value(of: move.to, color: color)
        assessment.advance = max(0, assessment.horseValueAfter - assessment.horseValueBefore)
        assessment.ownHorsesOnTrack = state.player(color)?.horses.filter { $0.trackSquare != nil }.count ?? 0
        if let square = move.to.trackSquare {
            assessment.reachesMouth = square == Board.mouthSquare(of: color)
            assessment.landsOnSafeSquare = Board.safeSquares(for: state.rules.safeSquares).contains(square)
        }
        assessment.threatBefore = threat(to: move.horse, in: state, exact: exactThreats)
        assessment.threatAfter = threat(to: move.horse, in: after, exact: exactThreats)
        if exactThreats, let player = after.player(color) {
            let rolls = GameRules.diceRange.filter { roll in
                player.horses.indices.contains { index in
                    MoveValidator.options(in: after, horse: HorseID(color, index), dice: [roll]).contains { !$0.captures.isEmpty }
                }
            }
            assessment.captureChanceNext = chance(ofAny: rolls.count, diceCount: after.rules.diceCount)
        }
        return assessment
    }

    /// Giá trị một quân theo quãng đường đã đi: 0 trong chuồng, 1...56 trên đường chạy, cao hơn trong cột đích.
    static func value(of position: HorsePosition, color: PlayerColor) -> Double {
        switch position {
        case .stable: 0
        case .track(let square): Double(1 + (Board.progress(ofSquare: square, for: color) ?? 0))
        case .home(let rung): Double(1 + Board.stepsToMouth + rung * 3)
        }
    }

    /// Xác suất quân `horse` bị đá trong một vòng, coi mỗi đối thủ đổ một lần.
    static func threat(to horse: HorseID, in state: GameState, exact: Bool) -> Double {
        guard let position = state.position(of: horse), let square = position.trackSquare else { return 0 }
        var survival = 1.0
        for opponent in state.players where opponent.color != horse.color && opponent.status == .active {
            var rolls = Set<Int>()
            for index in opponent.horses.indices {
                let attacker = HorseID(opponent.color, index)
                if exact {
                    // Xét mọi cách dùng một viên: đi thường và bay.
                    for roll in GameRules.diceRange
                    where MoveValidator.options(in: state, horse: attacker, dice: [roll]).contains(where: { $0.captures.contains(horse) }) {
                        rolls.insert(roll)
                    }
                } else if let from = opponent.horses[index].trackSquare {
                    // Ước lượng thô: đối phương đứng sau trong vòng 6 bước trên đường của họ (không xét cản đường hay
                    // ô an toàn). Quân đứng ở ô xuất phát của mình thì không ai tới được.
                    if let target = Board.progress(ofSquare: square, for: opponent.color),
                       let origin = Board.progress(ofSquare: from, for: opponent.color),
                       GameRules.diceRange.contains(target - origin) { rolls.insert(target - origin) }
                }
            }
            survival *= 1 - chance(ofAny: rolls.count, diceCount: state.rules.diceCount)
        }
        return 1 - survival
    }

    /// Xác suất ít nhất một viên ra một trong `count` giá trị. Với hai xúc xắc, nước cộng điểm không được tính
    /// (ước lượng thấp hơn thực tế một chút).
    static func chance(ofAny count: Int, diceCount: Int) -> Double {
        let single = Double(count) / Double(GameRules.diceRange.count)
        return 1 - pow(1 - single, Double(max(1, diceCount)))
    }
}
