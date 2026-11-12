/// Hành động người chơi gửi vào engine. Đây cũng là đơn vị truyền qua mạng.
public enum GameAction: Codable, Equatable, Sendable {
    /// Đổ xúc xắc. `second` là viên thứ hai, bắt buộc ở chế độ hai xúc xắc và không được có ở chế độ một xúc xắc.
    case roll(value: Int, second: Int? = nil)
    /// Đi một quân. `use` mặc định là đi theo viên đầu tiên còn lại.
    case move(horse: HorseID, use: DiceUse = .die(index: 0))
    case resign
}

public enum GameError: Error, Equatable, Sendable {
    case gameOver
    case notYourTurn
    case wrongPhase
    case invalidDiceValue
    case illegalMove
    case unknownPlayer
}

/// Những gì đã xảy ra sau một hành động, theo đúng thứ tự, để tầng hiển thị diễn hoạt.
public enum GameEvent: Equatable, Sendable {
    case rolled(player: PlayerColor, value: Int, second: Int? = nil)
    case moved(Move)
    case noLegalMove(player: PlayerColor, roll: Int)
    case bonusTurn(player: PlayerColor)
    case bonusLimitReached(player: PlayerColor)
    case turnChanged(to: PlayerColor)
    case resigned(player: PlayerColor)
    case gameOver(winner: PlayerColor)
}

/// Máy trạng thái của ván cờ. Mọi thay đổi trạng thái đều đi qua `apply`, vốn kiểm tra đầy đủ
/// lượt, pha và tính hợp lệ; một hành động bị từ chối không làm thay đổi trạng thái.
public struct GameEngine: Sendable {
    public private(set) var state: GameState

    public init(colors: [PlayerColor], rules: RulesConfiguration = .traditional) {
        self.state = GameState(colors: colors, rules: rules)
    }

    /// Khôi phục từ trạng thái đã lưu.
    public init(state: GameState) {
        self.state = state
    }

    /// Các nước đi hợp lệ của người chơi hiện tại (rỗng nếu chưa đổ xúc xắc).
    public var legalMoves: [Move] {
        guard case .awaitingMove = state.phase else { return [] }
        return MoveValidator.legalMoves(in: state, for: state.currentColor, dice: state.remainingDice)
    }

    /// Đổ xúc xắc bằng bộ sinh ngẫu nhiên cho trước rồi áp dụng kết quả.
    @discardableResult
    public mutating func roll<R: RandomNumberGenerator>(by color: PlayerColor, using generator: inout R) throws -> [GameEvent] {
        try apply(Self.randomRoll(rules: state.rules, using: &generator), by: color)
    }

    /// Hành động đổ xúc xắc ngẫu nhiên với đúng số viên của bộ luật.
    public static func randomRoll<R: RandomNumberGenerator>(rules: RulesConfiguration, using generator: inout R) -> GameAction {
        let first = Int.random(in: GameRules.diceRange, using: &generator)
        let second = rules.diceCount == 2 ? Int.random(in: GameRules.diceRange, using: &generator) : nil
        return .roll(value: first, second: second)
    }

    @discardableResult
    public mutating func apply(_ action: GameAction, by color: PlayerColor) throws -> [GameEvent] {
        guard !state.isFinished else { throw GameError.gameOver }
        guard let actor = state.player(color), actor.status == .active else { throw GameError.unknownPlayer }

        var next = state
        var events: [GameEvent] = []
        switch action {
        case .resign:
            Self.resign(color, in: &next, events: &events)
        case .roll(let value, let second):
            guard color == state.currentColor else { throw GameError.notYourTurn }
            guard state.phase == .awaitingRoll else { throw GameError.wrongPhase }
            let dice = [value] + (second.map { [$0] } ?? [])
            guard dice.count == state.rules.diceCount, dice.allSatisfy(GameRules.diceRange.contains) else { throw GameError.invalidDiceValue }
            Self.roll(dice, in: &next, events: &events)
        case .move(let horse, let use):
            guard color == state.currentColor else { throw GameError.notYourTurn }
            guard case .awaitingMove = state.phase else { throw GameError.wrongPhase }
            guard horse.color == color, let move = MoveValidator.resolve(use, in: state, horse: horse, dice: state.remainingDice) else {
                throw GameError.illegalMove
            }
            Self.perform(move, in: &next, events: &events)
        }
        next.actionCount += 1
        state = next
        return events
    }

    // MARK: - Chuyển trạng thái

    private static func roll(_ dice: [Int], in state: inout GameState, events: inout [GameEvent]) {
        let color = state.currentColor
        state.lastRoll = dice[0]
        state.rolledDice = dice
        state.remainingDice = dice
        events.append(.rolled(player: color, value: dice[0], second: dice.count > 1 ? dice[1] : nil))

        let bonus = TurnManager.grantsBonusTurn(dice: dice, rules: state.rules)
        if bonus {
            state.consecutiveBonusRolls += 1
            if TurnManager.exceedsBonusLimit(consecutiveBonusRolls: state.consecutiveBonusRolls, rules: state.rules) {
                events.append(.bonusLimitReached(player: color))
                state.remainingDice = []
                endTurn(in: &state, events: &events)
                return
            }
        }

        if MoveValidator.legalMoves(in: state, for: color, dice: dice).isEmpty {
            events.append(.noLegalMove(player: color, roll: dice[0]))
            state.remainingDice = []
            finishRoll(bonus: bonus, in: &state, events: &events)
        } else {
            state.phase = .awaitingMove(roll: dice[0])
        }
    }

    private static func perform(_ move: Move, in state: inout GameState, events: inout [GameEvent]) {
        let color = move.horse.color
        guard let index = state.playerIndex(of: color) else { return }
        // Bỏ các viên vừa dùng khỏi danh sách còn lại.
        switch move.use {
        case .die(let dieIndex): state.remainingDice.remove(at: dieIndex)
        case .sum: state.remainingDice = []
        case .fly: if let dieIndex = state.remainingDice.firstIndex(of: 1) { state.remainingDice.remove(at: dieIndex) }
        }
        state.players[index].horses[move.horse.index] = move.to
        for captured in move.captures {
            if let owner = state.playerIndex(of: captured.color) {
                state.players[owner].horses[captured.index] = .stable
            }
        }
        events.append(.moved(move))

        if state.players[index].hasWon {
            state.remainingDice = []
            state.phase = .finished(winner: color)
            events.append(.gameOver(winner: color))
            return
        }
        // Còn viên chưa dùng: tiếp tục nếu viên đó có nước đi, nếu không thì bỏ viên đó.
        if let next = state.remainingDice.first {
            if !MoveValidator.legalMoves(in: state, for: color, dice: state.remainingDice).isEmpty {
                state.phase = .awaitingMove(roll: next)
                return
            }
            events.append(.noLegalMove(player: color, roll: next))
            state.remainingDice = []
        }
        finishRoll(bonus: TurnManager.grantsBonusTurn(dice: state.rolledDice, rules: state.rules), in: &state, events: &events)
    }

    private static func finishRoll(bonus: Bool, in state: inout GameState, events: inout [GameEvent]) {
        if bonus {
            state.phase = .awaitingRoll
            events.append(.bonusTurn(player: state.currentColor))
        } else {
            endTurn(in: &state, events: &events)
        }
    }

    private static func endTurn(in state: inout GameState, events: inout [GameEvent]) {
        state.currentPlayerIndex = TurnManager.nextPlayerIndex(in: state)
        state.consecutiveBonusRolls = 0
        state.turnNumber += 1
        state.phase = .awaitingRoll
        events.append(.turnChanged(to: state.currentColor))
    }

    private static func resign(_ color: PlayerColor, in state: inout GameState, events: inout [GameEvent]) {
        guard let index = state.playerIndex(of: color) else { return }
        let wasCurrent = index == state.currentPlayerIndex
        state.players[index].status = .resigned
        state.players[index].horses = Array(repeating: .stable, count: Board.horsesPerPlayer)
        events.append(.resigned(player: color))

        let remaining = state.players.filter { $0.status == .active }
        if remaining.count == 1, let last = remaining.first {
            state.phase = .finished(winner: last.color)
            events.append(.gameOver(winner: last.color))
        } else if wasCurrent {
            endTurn(in: &state, events: &events)
        }
    }
}
