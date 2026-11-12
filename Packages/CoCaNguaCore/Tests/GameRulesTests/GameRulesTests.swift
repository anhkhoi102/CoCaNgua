import Foundation
import Testing
@testable import GameCore

@Suite("Luật chơi truyền thống")
struct TraditionalRulesTests {
    @Test func initialState() {
        let state = GameState(colors: [.green, .red])
        #expect(state.players.map(\.color) == [.red, .green])
        #expect(state.currentColor == .red)
        #expect(state.phase == .awaitingRoll)
        #expect(state.players.allSatisfy { $0.horses == Array(repeating: .stable, count: 4) })
    }

    @Test func boardGeometry() {
        #expect(Board.trackLength == 56)
        #expect(Board.startSquare(of: .red) == 0)
        #expect(Board.startSquare(of: .blue) == 14)
        #expect(Board.mouthSquare(of: .red) == 55)
        #expect(Board.mouthSquare(of: .blue) == 13)
        // Ô xuất phát nằm ngoài đường chạy: một vòng là 52 bước, ô xuất phát của màu khác không thuộc quãng đường.
        #expect(Board.stepsToMouth == 52)
        #expect(Board.progress(ofSquare: 13, for: .blue) == 52)
        #expect(Board.progress(ofSquare: 0, for: .red) == 0)
        #expect(Board.progress(ofSquare: 14, for: .red) == nil)
        #expect(Board.progress(ofSquare: 15, for: .red) == 14)
        #expect(Board.square(atProgress: 14, for: .red) == 15)
        for color in PlayerColor.allCases {
            let lap = (0...Board.stepsToMouth).map { Board.square(atProgress: $0, for: color) }
            #expect(Set(lap).count == 53)
            #expect(lap.dropFirst().allSatisfy { !Board.isStartSquare($0) })
            #expect(lap.enumerated().allSatisfy { Board.progress(ofSquare: $0.element, for: color) == $0.offset })
        }
    }

    @Test(arguments: 1...5)
    func nonSixWithAllHorsesInStablePassesTurn(roll: Int) throws {
        var engine = GameEngine(colors: [.red, .green])
        let events = try engine.apply(.roll(value: roll), by: .red)
        #expect(events == [.rolled(player: .red, value: roll), .noLegalMove(player: .red, roll: roll), .turnChanged(to: .green)])
        #expect(engine.state.currentColor == .green)
        #expect(engine.state.phase == .awaitingRoll)
    }

    @Test func sixReleasesHorseAndGrantsAnotherRoll() throws {
        var engine = GameEngine(colors: [.red, .green])
        try engine.apply(.roll(value: 6), by: .red)
        #expect(engine.state.phase == .awaitingMove(roll: 6))
        #expect(engine.legalMoves.count == 4)
        #expect(engine.legalMoves.allSatisfy { $0.kind == .release })

        let events = try engine.apply(.move(horse: HorseID(.red, 2)), by: .red)
        #expect(engine.state.player(.red)!.horses[2] == .track(0))
        #expect(events.last == .bonusTurn(player: .red))
        #expect(engine.state.currentColor == .red)
        #expect(engine.state.phase == .awaitingRoll)
    }

    @Test func normalMovementAdvancesClockwiseAndEndsTurn() throws {
        var engine = GameEngine(state: makeState(horses: [.green: [.track(11)]], current: .green))
        try engine.apply(.roll(value: 4), by: .green)
        let events = try engine.apply(.move(horse: HorseID(.green, 0)), by: .green)
        // Từ ô 11 đi 4 bước: 12, 13, rồi nhảy qua ô 14 (ô xuất phát của Xanh dương, không tính bước), 15, 16.
        #expect(engine.state.player(.green)!.horses[0] == .track(16))
        guard case .moved(let move) = events[0] else { Issue.record("thiếu sự kiện moved"); return }
        #expect(move.path == [.track(12), .track(13), .track(15), .track(16)])
        #expect(engine.state.currentColor == .red)
    }

    @Test func landingExactlyOnOpponentCapturesIt() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(10)], .green: [.track(13)]]))
        try engine.apply(.roll(value: 3), by: .red)
        let events = try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(13))
        #expect(engine.state.player(.green)!.horses[0] == .stable)
        guard case .moved(let move) = events[0] else { Issue.record("thiếu sự kiện moved"); return }
        #expect(move.captures == [HorseID(.green, 0)])
    }

    @Test func horseCannotJumpOverAnyHorse() {
        let state = makeState(horses: [.red: [.track(10), .track(12)], .green: [.track(20)]])
        // Quân đỏ #0 bị quân đỏ #1 cản khi đổ 3 trở lên, và không được đứng chung ô khi đổ 2.
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 1) != nil)
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 2) == nil)
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 3) == nil)
        // Quân đỏ #1 cách quân xanh 8 ô: đổ 6 vẫn đi được.
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 1), roll: 6) != nil)
        let blocked = makeState(horses: [.red: [.track(16)], .green: [.track(20)]])
        #expect(MoveValidator.move(in: blocked, horse: HorseID(.red, 0), roll: 5) == nil)
        #expect(MoveValidator.move(in: blocked, horse: HorseID(.red, 0), roll: 4)?.captures == [HorseID(.green, 0)])
    }

    @Test func releaseCapturesOpponentOnStartSquareButNotOwnHorse() {
        let enemy = makeState(horses: [.green: [.track(0)]])
        #expect(MoveValidator.move(in: enemy, horse: HorseID(.red, 0), roll: 6)?.captures == [HorseID(.green, 0)])
        let own = makeState(horses: [.red: [.track(0)]])
        #expect(MoveValidator.move(in: own, horse: HorseID(.red, 1), roll: 6) == nil)
    }

    @Test func startSquaresBelongToTheirOwnColourOnly() throws {
        // Quân Xanh lá đứng ngay trước ô xuất phát của Đỏ (ô 0) và có quân Đỏ đang chờ ở đó.
        let state = makeState(horses: [.red: [.track(0)], .green: [.track(55)]], current: .green)
        for roll in 1...6 {
            let move = MoveValidator.move(in: state, horse: HorseID(.green, 0), roll: roll)
            // Không nước nào dừng ở ô 0, không đá được quân đang chờ, và quân đó không cản đường.
            #expect(move?.to == .track(roll))
            #expect(move?.captures == [])
            #expect(move?.path.contains(.track(0)) == false)
        }
        // Ra quân khi ô xuất phát của mình còn quân đứng thì không được (không chồng quân).
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 1), roll: 6) == nil)
        // Không quân nào của màu khác tới được ô xuất phát của Đỏ, từ bất kỳ đâu.
        for square in 0..<Board.trackLength where !Board.isStartSquare(square) {
            let probe = makeState(horses: [.green: [.track(square)]], current: .green)
            for roll in 1...6 {
                let options = MoveValidator.options(in: probe, horse: HorseID(.green, 0), dice: [roll])
                #expect(options.allSatisfy { move in move.path.allSatisfy { $0.trackSquare.map(Board.isStartSquare) != true } })
            }
        }
    }

    @Test func horseMustStopExactlyAtTheMouth() {
        let state = makeState(horses: [.red: [sq(Board.stepsToMouth - 3, .red)]])
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 3)?.to == .track(55))
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 4) == nil)
    }

    @Test func fromTheMouthTheRollIsTheRungReached() {
        let state = makeState(horses: [.red: [sq(Board.stepsToMouth, .red)]])
        for roll in 1...6 {
            let move = MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: roll)
            #expect(move?.to == .home(roll))
            #expect(move?.kind == .climb)
        }
        // Bậc 3 có quân: không lên được bậc 3 và không nhảy qua nó.
        let occupied = makeState(horses: [.red: [sq(Board.stepsToMouth, .red), .home(3)]])
        #expect(MoveValidator.move(in: occupied, horse: HorseID(.red, 0), roll: 2)?.to == .home(2))
        #expect(MoveValidator.move(in: occupied, horse: HorseID(.red, 0), roll: 3) == nil)
        #expect(MoveValidator.move(in: occupied, horse: HorseID(.red, 0), roll: 5) == nil)
    }

    @Test func climbingInsideTheColumnNeedsTheExactNextRung() {
        let state = makeState(horses: [.red: [.home(3), .home(5)]])
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 4)?.to == .home(4))
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 3) == nil)
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 5) == nil)
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 1), roll: 6)?.to == .home(6))
        let top = makeState(horses: [.red: [.home(6)]])
        #expect((1...6).allSatisfy { MoveValidator.move(in: top, horse: HorseID(.red, 0), roll: $0) == nil })
    }

    @Test func horseAtTheMouthCanStillBeCaptured() {
        let state = makeState(horses: [.red: [sq(Board.stepsToMouth, .red)], .green: [.track(52)]], current: .green)
        #expect(MoveValidator.move(in: state, horse: HorseID(.green, 0), roll: 3)?.captures == [HorseID(.red, 0)])
    }

    @Test func playerWinsWithHorsesOnRungsSixFiveFourThree() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.home(6), .home(5), .home(4), .home(2)]]))
        try engine.apply(.roll(value: 3), by: .red)
        let events = try engine.apply(.move(horse: HorseID(.red, 3)), by: .red)
        #expect(events.last == .gameOver(winner: .red))
        #expect(engine.state.winner == .red)
        #expect(engine.state.standings() == [.red, .green])
    }

    @Test func fourHorsesHomeButNotOnTopRungsIsNotAWin() {
        #expect(!Player(color: .red, horses: [.home(6), .home(5), .home(4), .home(2)]).hasWon)
        #expect(Player(color: .red, horses: [.home(3), .home(6), .home(4), .home(5)]).hasWon)
    }

    @Test func sixWithNoLegalMoveStillGrantsAnotherRoll() throws {
        // Quân duy nhất ngoài chuồng đang ở bậc 6; ô xuất phát bị quân mình chiếm nên không ra quân được.
        var engine = GameEngine(state: makeState(horses: [.red: [.track(0), .home(6), .home(5), .home(4)]]))
        // Quân trên ô xuất phát đi 6 được, nên chặn nó bằng một quân xanh ở giữa đường.
        var state = engine.state
        state.players[1].horses[0] = .track(3)
        engine = GameEngine(state: state)
        let events = try engine.apply(.roll(value: 6), by: .red)
        #expect(events == [.rolled(player: .red, value: 6), .noLegalMove(player: .red, roll: 6), .bonusTurn(player: .red)])
        #expect(engine.state.currentColor == .red)
    }

    @Test func turnsRotateClockwiseAndSkipResignedPlayers() throws {
        var engine = GameEngine(colors: [.red, .blue, .green, .yellow])
        try engine.apply(.roll(value: 2), by: .red)
        #expect(engine.state.currentColor == .blue)
        try engine.apply(.resign, by: .green)
        try engine.apply(.roll(value: 2), by: .blue)
        #expect(engine.state.currentColor == .yellow)
        try engine.apply(.roll(value: 2), by: .yellow)
        #expect(engine.state.currentColor == .red)
        #expect(engine.state.turnNumber == 4)
    }

    @Test func resigningRemovesHorsesAndLastPlayerStandingWins() throws {
        var engine = GameEngine(state: makeState([.red, .blue, .green], horses: [.red: [.track(5), .home(2)]]))
        let first = try engine.apply(.resign, by: .red)
        #expect(first == [.resigned(player: .red), .turnChanged(to: .blue)])
        #expect(engine.state.player(.red)!.horses == Array(repeating: .stable, count: 4))
        let second = try engine.apply(.resign, by: .green)
        #expect(second == [.resigned(player: .green), .gameOver(winner: .blue)])
        #expect(engine.state.standings().first == .blue)
    }
}

@Suite("Biến thể luật")
struct RuleVariantTests {
    @Test func oneOrSixVariantReleasesAndGrantsBonusOnOne() throws {
        var rules = RulesConfiguration.traditional
        rules.releaseValues = [1, 6]
        rules.bonusTurnValues = [1, 6]
        var engine = GameEngine(colors: [.red, .green], rules: rules)
        try engine.apply(.roll(value: 1), by: .red)
        let events = try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(0))
        #expect(events.last == .bonusTurn(player: .red))
    }

    @Test func stepwiseEntryNeedsAOneFromTheMouth() {
        var rules = RulesConfiguration.traditional
        rules.homeEntry = .exactRungStepwise
        let state = makeState(rules: rules, horses: [.red: [sq(Board.stepsToMouth, .red)]])
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 1)?.to == .home(1))
        #expect((2...6).allSatisfy { MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: $0) == nil })
    }

    @Test func thirdConsecutiveSixForfeitsTheTurn() throws {
        var rules = RulesConfiguration.traditional
        rules.maxConsecutiveBonusRolls = 3
        var engine = GameEngine(colors: [.red, .green], rules: rules)
        for _ in 0..<2 {
            try engine.apply(.roll(value: 6), by: .red)
            try engine.apply(engine.legalMoves[0].action, by: .red)
        }
        let before = engine.state.player(.red)!.horses
        let events = try engine.apply(.roll(value: 6), by: .red)
        #expect(events == [.rolled(player: .red, value: 6), .bonusLimitReached(player: .red), .turnChanged(to: .green)])
        #expect(engine.state.player(.red)!.horses == before)
        #expect(engine.state.consecutiveBonusRolls == 0)
    }

    @Test func unlimitedConsecutiveSixesByDefault() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(0)]]))
        for _ in 0..<5 {
            try engine.apply(.roll(value: 6), by: .red)
            try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        }
        #expect(engine.state.currentColor == .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(32))
    }

    @Test func safeSquaresPreventCaptureAndAllowSharing() throws {
        var rules = RulesConfiguration.traditional
        rules.safeSquares = .startAndMidSquares
        // Ô xuất phát vốn là ô riêng của từng màu nên chỉ còn các ô giữa cạnh là ô an toàn.
        #expect(Board.safeSquares(for: .startSquares).isEmpty)
        #expect(Board.safeSquares(for: .startAndMidSquares) == [7, 21, 35, 49])
        var engine = GameEngine(state: makeState(rules: rules, horses: [.red: [.track(4)], .green: [.track(7)]]))
        try engine.apply(.roll(value: 3), by: .red)
        try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        #expect(engine.state.horses(onTrack: 7).count == 2)
        #expect(engine.state.player(.green)!.horses[0] == .track(7))
    }

    @Test func stackingAllowsSharingAndProtectsTheStack() {
        var rules = RulesConfiguration.traditional
        rules.allowStacking = true
        let state = makeState(rules: rules, horses: [.red: [.track(10), .track(12)], .green: [.track(20), .track(20), .track(17)]])
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 2)?.to == .track(12))
        // Hai quân xanh chồng ở ô 20 không bị đá; quân lẻ ở ô 17 thì bị.
        let attacker = makeState(rules: rules, horses: [.red: [.track(16)], .green: [.track(20), .track(20), .track(17)]])
        #expect(MoveValidator.move(in: attacker, horse: HorseID(.red, 0), roll: 4) == nil)
        #expect(MoveValidator.move(in: attacker, horse: HorseID(.red, 0), roll: 1)?.captures == [HorseID(.green, 2)])
    }

    @Test func withoutBlockingHorsesMayPassEachOther() {
        var rules = RulesConfiguration.traditional
        rules.blocking = false
        let state = makeState(rules: rules, horses: [.red: [.track(10)], .green: [.track(12)]])
        #expect(MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 5)?.to == .track(16))
    }

    @Test func pipCountEntryWalksIntoTheColumnWithoutOvershoot() {
        let state = makeState(rules: .modern, horses: [.red: [sq(Board.stepsToMouth - 2, .red)]])
        let move = MoveValidator.move(in: state, horse: HorseID(.red, 0), roll: 5)
        #expect(move?.path == [.track(54), .track(55), .home(1), .home(2), .home(3)])
        let near = makeState(rules: .modern, horses: [.red: [.home(4)]])
        #expect(MoveValidator.move(in: near, horse: HorseID(.red, 0), roll: 2)?.to == .home(6))
        #expect(MoveValidator.move(in: near, horse: HorseID(.red, 0), roll: 3) == nil)
    }

    @Test func invalidConfigurationsAreDetected() {
        var rules = RulesConfiguration.traditional
        #expect(rules.isValid())
        rules.releaseValues = []
        #expect(!rules.isValid())
        rules = .traditional
        rules.bonusTurnValues = [7]
        #expect(!rules.isValid())
    }
}

@Suite("Lưu trạng thái và mô phỏng")
struct StateTests {
    @Test func stateSurvivesJSONRoundTrip() throws {
        var engine = GameEngine(state: makeState([.red, .blue, .yellow], rules: .modern,
                                                 horses: [.red: [.track(7), .home(2)], .yellow: [.track(50)]]))
        try engine.apply(.roll(value: 4), by: .red)
        let data = try JSONEncoder().encode(engine.state)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == engine.state)
    }

    @Test func corruptHorsePositionIsRejected() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([HorsePosition].self, from: Data("[77]".utf8)) }
    }

    /// Chơi ngẫu nhiên trọn ván: phải luôn kết thúc với đúng một người thắng và không vi phạm bất biến.
    @Test(arguments: [RulesConfiguration.traditional, .modern], [2, 3, 4])
    func randomGamesAlwaysFinish(rules: RulesConfiguration, playerCount: Int) throws {
        for seed in 0..<20 {
            var generator = SeededGenerator(seed: UInt64(seed))
            var engine = GameEngine(colors: GameRules.defaultColors(playerCount: playerCount), rules: rules)
            var actions = 0
            while !engine.state.isFinished {
                actions += 1
                try #require(actions < 200_000, "ván không kết thúc (seed \(seed))")
                let color = engine.state.currentColor
                if engine.state.phase == .awaitingRoll {
                    try engine.roll(by: color, using: &generator)
                } else {
                    let moves = engine.legalMoves
                    try #require(!moves.isEmpty)
                    try engine.apply(moves.randomElement(using: &generator)!.action, by: color)
                }
                checkInvariants(engine.state)
            }
            #expect(engine.state.player(engine.state.winner!)!.hasWon)
        }
    }

    private func checkInvariants(_ state: GameState) {
        for player in state.players {
            let rungs = player.horses.compactMap(\.homeRung)
            #expect(Set(rungs).count == rungs.count, "hai quân chung một bậc đích")
        }
        guard !state.rules.allowStacking, state.rules.safeSquares == .none else { return }
        let squares = state.players.flatMap { $0.horses.compactMap(\.trackSquare) }
        #expect(Set(squares).count == squares.count, "hai quân chung một ô")
    }
}
