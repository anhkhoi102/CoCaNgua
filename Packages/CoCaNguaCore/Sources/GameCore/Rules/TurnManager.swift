/// Quy tắc chuyển lượt và đổ thêm.
public enum TurnManager {
    /// Một xúc xắc: được đổ thêm khi ra giá trị thưởng (mặc định là 6). Hai xúc xắc: chỉ khi ra đôi.
    public static func grantsBonusTurn(dice: [Int], rules: RulesConfiguration) -> Bool {
        if dice.count == 2 { return dice[0] == dice[1] }
        return dice.first.map(rules.bonusTurnValues.contains) ?? false
    }

    /// Lần đổ thưởng này có chạm giới hạn đổ thưởng liên tiếp không (khi đó bị huỷ và mất lượt).
    public static func exceedsBonusLimit(consecutiveBonusRolls: Int, rules: RulesConfiguration) -> Bool {
        guard let limit = rules.maxConsecutiveBonusRolls else { return false }
        return consecutiveBonusRolls >= limit
    }

    /// Chỉ số người chơi còn hoạt động kế tiếp theo thứ tự lượt.
    public static func nextPlayerIndex(in state: GameState) -> Int {
        let count = state.players.count
        for offset in 1...count {
            let index = (state.currentPlayerIndex + offset) % count
            if state.players[index].status == .active { return index }
        }
        return state.currentPlayerIndex
    }
}
