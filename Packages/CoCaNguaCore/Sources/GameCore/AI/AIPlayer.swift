/// Mức độ của đối thủ máy. Mức độ chỉ thay đổi chất lượng quyết định, không bao giờ can thiệp xúc xắc.
public enum AIDifficulty: String, Codable, CaseIterable, Sendable {
    /// Phần lớn đi ngẫu nhiên, thỉnh thoảng mới chọn nước tốt; không bỏ lỡ nước thắng ngay.
    case easy
    /// Biết đá quân, ra quân, lên đích và né nguy hiểm theo ước lượng thô; đôi lúc chọn chưa tối ưu.
    case normal
    /// Tính chính xác khả năng bị đá sau mỗi nước, cân nhắc giá trị từng quân, không có yếu tố ngẫu nhiên
    /// (trừ khi hai nước ngang điểm).
    case hard
}

/// Đối thủ máy. Chỉ chọn trong các nước `MoveValidator` đã xác nhận hợp lệ, nên luôn tuân theo đúng luật của người chơi.
public struct AIPlayer: Sendable {
    public let difficulty: AIDifficulty

    public init(difficulty: AIDifficulty) {
        self.difficulty = difficulty
    }

    /// Chọn một nước trong `moves` (không rỗng).
    public func chooseMove<R: RandomNumberGenerator>(from moves: [Move], in state: GameState, using generator: inout R) -> Move {
        precondition(!moves.isEmpty, "Không có nước nào để chọn")
        guard moves.count > 1 else { return moves[0] }
        switch difficulty {
        case .easy:
            let assessments = AIStrategy.assess(moves, in: state, exactThreats: false)
            if let winning = assessments.first(where: \.wins) { return winning.move }
            if Double.random(in: 0..<1, using: &generator) < 0.15 {
                return best(assessments, noise: 0, using: &generator)
            }
            return moves.randomElement(using: &generator)!
        case .normal:
            return best(AIStrategy.assess(moves, in: state, exactThreats: false), noise: 12, using: &generator)
        case .hard:
            return best(AIStrategy.assess(moves, in: state, exactThreats: true), noise: 0, using: &generator)
        }
    }

    private func best<R: RandomNumberGenerator>(_ assessments: [MoveAssessment], noise: Double, using generator: inout R) -> Move {
        var bestScore = -Double.infinity
        var candidates: [Move] = []
        for assessment in assessments {
            var score = self.score(assessment)
            if noise > 0 { score += Double.random(in: -noise...noise, using: &generator) }
            if score > bestScore + 1e-9 {
                bestScore = score
                candidates = [assessment.move]
            } else if abs(score - bestScore) <= 1e-9 {
                candidates.append(assessment.move)
            }
        }
        return candidates.randomElement(using: &generator) ?? assessments[0].move
    }

    /// Điểm của một nước. Các trọng số được chỉnh bằng cách cho máy đấu với nhau (xem AITests).
    func score(_ a: MoveAssessment) -> Double {
        if a.wins { return 1_000_000 }
        var score = a.advance
        if a.captureValue > 0 { score += 45 + a.captureValue * 1.1 }
        switch a.move.kind {
        case .release:
            // Càng ít quân trên bàn càng cần ra quân.
            score += a.ownHorsesOnTrack == 0 ? 55 : 28
        case .climb:
            score += 30 + Double(a.rungReached) * 5
        case .advance, .fly:
            if a.reachesMouth { score += 22 }
        }
        if a.landsOnSafeSquare { score += 14 }
        // Mất một quân là mất quãng đường nó đã đi, cộng thêm thời gian chờ ra quân lại.
        score -= a.threatAfter * (a.horseValueAfter + 22) * 1.25
        score += a.threatBefore * (a.horseValueBefore + 22) * 0.9
        // Đứng vào vị trí có thể đá quân ở lượt sau (chỉ mức Khó tính được).
        score += a.captureChanceNext * 14
        return score
    }
}
