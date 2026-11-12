import GameCore
import Testing

/// Cho các mức máy đấu với nhau và đếm số ván thắng của từng màu.
func playMatches(_ count: Int, seats: [PlayerColor: AIDifficulty], rules: RulesConfiguration = .traditional, seed: UInt64) throws -> [PlayerColor: Int] {
    var wins: [PlayerColor: Int] = [:]
    var generator = SeededGenerator(seed: seed)
    for game in 0..<count {
        var engine = GameEngine(colors: Array(seats.keys), rules: rules)
        // Luân phiên người đi trước để không màu nào được lợi thế.
        var state = engine.state
        state.currentPlayerIndex = game % state.players.count
        engine = GameEngine(state: state)
        var actions = 0
        while !engine.state.isFinished {
            actions += 1
            try #require(actions < 300_000, "ván không kết thúc")
            let color = engine.state.currentColor
            if engine.state.phase == .awaitingRoll {
                try engine.roll(by: color, using: &generator)
            } else {
                let move = AIPlayer(difficulty: seats[color]!).chooseMove(from: engine.legalMoves, in: engine.state, using: &generator)
                try engine.apply(move.action, by: color)
            }
        }
        wins[engine.state.winner!, default: 0] += 1
    }
    return wins
}

@Suite("Đối thủ máy")
struct AITests {
    @Test(arguments: AIDifficulty.allCases)
    func everyDifficultyOnlyPicksLegalMoves(difficulty: AIDifficulty) {
        let state = makeState(horses: [.red: [.track(0), .track(4), sq(Board.stepsToMouth, .red), .home(2)], .green: [.track(6)]])
        var generator = SeededGenerator(seed: 1)
        for roll in 1...6 {
            let moves = MoveValidator.legalMoves(in: state, for: .red, roll: roll)
            guard !moves.isEmpty else { continue }
            var awaiting = state
            awaiting.phase = .awaitingMove(roll: roll)
            awaiting.rolledDice = [roll]
            awaiting.remainingDice = [roll]
            for _ in 0..<20 {
                #expect(moves.contains(AIPlayer(difficulty: difficulty).chooseMove(from: moves, in: awaiting, using: &generator)))
            }
        }
    }

    @Test(arguments: AIDifficulty.allCases)
    func sameSeedGivesSameDecisions(difficulty: AIDifficulty) {
        var state = makeState(horses: [.red: [.track(0), .track(4), .track(9)], .green: [.track(12)]])
        state.phase = .awaitingMove(roll: 2)
            state.rolledDice = [2]
            state.remainingDice = [2]
        let moves = MoveValidator.legalMoves(in: state, for: .red, roll: 2)
        var a = SeededGenerator(seed: 7), b = SeededGenerator(seed: 7)
        let ai = AIPlayer(difficulty: difficulty)
        #expect((0..<10).map { _ in ai.chooseMove(from: moves, in: state, using: &a) }
            == (0..<10).map { _ in ai.chooseMove(from: moves, in: state, using: &b) })
    }

    private func choice(_ difficulty: AIDifficulty, roll: Int, rules: RulesConfiguration = .traditional,
                        horses: [PlayerColor: [HorsePosition]], seed: UInt64 = 5) -> Move {
        var state = makeState(rules: rules, horses: horses)
        state.phase = .awaitingMove(roll: roll)
            state.rolledDice = [roll]
            state.remainingDice = [roll]
        var generator = SeededGenerator(seed: seed)
        return AIPlayer(difficulty: difficulty).chooseMove(from: MoveValidator.legalMoves(in: state, for: .red, roll: roll),
                                                         in: state, using: &generator)
    }

    @Test(arguments: [AIDifficulty.normal, .hard])
    func takesACaptureWhenOneIsAvailable(difficulty: AIDifficulty) {
        // Quân #0 đá được quân xanh ở ô 13; quân #1 chỉ đi tiếp bình thường.
        let move = choice(difficulty, roll: 3, horses: [.red: [.track(10), .track(30)], .green: [.track(13), .track(50)]])
        #expect(move.horse == HorseID(.red, 0))
        #expect(move.captures == [HorseID(.green, 0)])
    }

    @Test(arguments: AIDifficulty.allCases)
    func neverMissesAWinningMove(difficulty: AIDifficulty) {
        for seed in 0..<20 {
            let move = choice(difficulty, roll: 3, horses: [.red: [.home(6), .home(5), .home(4), .home(2)] , .green: [.track(1)]], seed: UInt64(seed))
            #expect(move.to == .home(3))
        }
    }

    @Test func hardAvoidsSteppingIntoDangerWhenASafeMoveExists() {
        // Đổ 2: quân #0 sẽ đứng ngay trước mặt quân xanh (cách 3 ô); quân #1 đi ở nơi không ai với tới.
        let move = choice(.hard, roll: 2, horses: [.red: [.track(8), .track(30), .home(6), .home(5)], .green: [.track(7), .stable]])
        #expect(move.horse == HorseID(.red, 1))
    }

    @Test func hardMovesAThreatenedHorseOutOfReach() {
        // Quân #0 đang bị quân xanh đứng sau 2 ô đe doạ; đổ 6 đưa nó ra khỏi tầm (cách 8 ô).
        let move = choice(.hard, roll: 6, horses: [.red: [.track(12), .track(40), .home(6), .home(5)], .green: [.track(10), .stable]])
        #expect(move.horse == HorseID(.red, 0))
    }

    @Test func hardKnowsABlockedAttackerIsNotAThreat() {
        // Quân xanh đứng sau 4 ô nhưng bị một quân khác cản đường, nên không đá được: ước lượng thô coi là nguy hiểm,
        // còn mức Khó tính đúng là an toàn.
        let horses: [PlayerColor: [HorsePosition]] = [.red: [.track(15), .stable], .green: [.track(10), .track(12)]]
        var state = makeState(horses: horses)
        state.phase = .awaitingMove(roll: 1)
            state.rolledDice = [1]
            state.remainingDice = [1]
        let rough = AIStrategy.assess(MoveValidator.legalMoves(in: state, for: .red, roll: 1), in: state, exactThreats: false)[0]
        let exact = AIStrategy.assess(MoveValidator.legalMoves(in: state, for: .red, roll: 1), in: state, exactThreats: true)[0]
        // Trước khi đi: quân đỏ ở ô 15, quân xanh ở ô 12 cách 2 bước (ô 14 là ô xuất phát, không tính) (đá được), quân ở ô 10 bị cản.
        #expect(rough.threatBefore > exact.threatBefore)
        #expect(abs(exact.threatBefore - 1.0 / 6) < 1e-9)
    }

    @Test func hardPrefersHomeProgressOverAPlainStep() {
        let move = choice(.hard, roll: 4, horses: [.red: [sq(Board.stepsToMouth, .red), .track(20)], .green: [.stable]])
        #expect(move.to == .home(4))
    }

    @Test func releasesAHorseWhenNoneAreOnTheBoard() {
        for difficulty in [AIDifficulty.normal, .hard] {
            let move = choice(difficulty, roll: 6, horses: [.red: [.home(2), .stable, .stable, .stable], .green: [.track(40)]])
            #expect(move.kind == .release, "\(difficulty)")
        }
    }

    @Test func respectsSafeSquaresUnderModernRules() {
        // Luật hiện đại: ô 7 là ô an toàn (giữa cạnh). Mức Khó chọn đứng vào đó thay vì đứng trước mặt đối thủ.
        var rules = RulesConfiguration.modern
        rules.allowStacking = false
        let move = choice(.hard, roll: 2, rules: rules, horses: [.red: [.track(5), .track(20)], .green: [.track(3), .track(19)]])
        #expect(move.to == .track(7))
    }

    /// Mức cao hơn phải thắng mức thấp hơn rõ rệt. Hạt giống cố định nên kết quả lặp lại được.
    @Test func strongerDifficultiesWinMoreOften() throws {
        let games = 200
        let hardVsEasy = try playMatches(games, seats: [.red: .hard, .green: .easy], seed: 11)
        let normalVsEasy = try playMatches(games, seats: [.red: .normal, .green: .easy], seed: 12)
        let hardVsNormal = try playMatches(games, seats: [.red: .hard, .green: .normal], seed: 13)
        print("AI: Khó–Dễ \(hardVsEasy[.red] ?? 0)/\(games), Thường–Dễ \(normalVsEasy[.red] ?? 0)/\(games), Khó–Thường \(hardVsNormal[.red] ?? 0)/\(games)")
        #expect(Double(hardVsEasy[.red] ?? 0) / Double(games) > 0.65)
        #expect(Double(normalVsEasy[.red] ?? 0) / Double(games) > 0.56)
        #expect(Double(hardVsNormal[.red] ?? 0) / Double(games) > 0.54)
    }

    @Test func hardFliesWhenItGainsTheMostGround() {
        // Đổ 1: đi một bước tới ô 4, hoặc bay tới ô cửa chuồng kế tiếp (ô 13). Không có nguy hiểm ở đâu cả.
        let move = choice(.hard, roll: 1, horses: [.red: [.track(3), .home(6), .home(5), .home(4)], .green: [.stable]])
        #expect(move.kind == .fly)
    }

    @Test(arguments: AIDifficulty.allCases)
    func everyDifficultyPlaysSpeedModeToTheEnd(difficulty: AIDifficulty) throws {
        var rules = RulesConfiguration.traditional
        rules.diceCount = 2
        let wins = try playMatches(4, seats: [.red: difficulty, .blue: .easy, .green: difficulty, .yellow: .normal], rules: rules, seed: 31)
        #expect(wins.values.reduce(0, +) == 4)
    }

    @Test(arguments: [RulesConfiguration.traditional, .modern])
    func fourMixedAIsFinishAGame(rules: RulesConfiguration) throws {
        let wins = try playMatches(6, seats: [.red: .hard, .blue: .normal, .green: .easy, .yellow: .hard], rules: rules, seed: 21)
        #expect(wins.values.reduce(0, +) == 6)
    }
}
