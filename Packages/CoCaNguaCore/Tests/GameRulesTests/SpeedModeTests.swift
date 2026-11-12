import Foundation
import Testing
@testable import GameCore

private var speedRules: RulesConfiguration {
    var rules = RulesConfiguration.traditional
    rules.diceCount = 2
    return rules
}

/// Trạng thái ngay sau khi người đang tới lượt đổ ra `dice`.
private func rolled(_ dice: [Int], rules: RulesConfiguration = speedRules, horses: [PlayerColor: [HorsePosition]],
                    colors: [PlayerColor] = [.red, .green]) throws -> GameEngine {
    var engine = GameEngine(state: makeState(colors, rules: rules, horses: horses))
    try engine.apply(.roll(value: dice[0], second: dice.count > 1 ? dice[1] : nil), by: engine.state.currentColor)
    return engine
}

@Suite("Nước bay")
struct FlightTests {
    @Test(arguments: [(0, 13), (3, 13), (12, 13), (13, 26), (20, 26), (26, 39), (39, 52), (51, 52)])
    func aOneFliesToTheNextGateAhead(from: Int, to: Int) {
        let state = makeState(horses: [.red: [sq(from, .red)]])
        let flights = MoveValidator.options(in: state, horse: HorseID(.red, 0), dice: [1]).filter { $0.kind == .fly }
        #expect(flights.count == 1)
        #expect(flights.first?.to == sq(to, .red))
        #expect(flights.first?.path == [sq(to, .red)])
        #expect(flights.first?.use == .fly)
    }

    @Test func everyColourFliesAlongItsOwnLap() {
        // Xanh lá xuất phát ở ô 28; từ ô xuất phát bay tới ô cửa chuồng đầu tiên trên đường của nó (ô 41).
        let state = makeState(horses: [.green: [.track(28)]], current: .green)
        let flight = MoveValidator.resolve(.fly, in: state, horse: HorseID(.green, 0), dice: [1])
        #expect(flight?.to == .track(41))
        // Ô cửa chuồng xa nhất phía trước luôn là của chính mình: không bao giờ bay quá.
        let last = makeState(horses: [.green: [sq(50, .green)]], current: .green)
        #expect(MoveValidator.resolve(.fly, in: last, horse: HorseID(.green, 0), dice: [1])?.to == .track(Board.mouthSquare(of: .green)))
    }

    @Test func onlyAOneAllowsFlyingAndTheStepRemainsAvailable() {
        let state = makeState(horses: [.red: [.track(3)]])
        for roll in 2...6 {
            #expect(MoveValidator.options(in: state, horse: HorseID(.red, 0), dice: [roll]).map(\.kind) == [.advance])
        }
        let options = MoveValidator.options(in: state, horse: HorseID(.red, 0), dice: [1])
        #expect(Set(options.map(\.to)) == [.track(4), .track(13)])
    }

    @Test func horsesInTheStableHomeColumnOrAtTheirOwnGateCannotFly() {
        let state = makeState(horses: [.red: [.stable, .home(2), sq(Board.stepsToMouth, .red)]])
        for index in 0..<3 {
            #expect(MoveValidator.resolve(.fly, in: state, horse: HorseID(.red, index), dice: [1]) == nil)
        }
        // Ở cửa chuồng, viên 1 dùng để lên bậc 1 như thường.
        #expect(MoveValidator.options(in: state, horse: HorseID(.red, 2), dice: [1]).map(\.to) == [.home(1)])
    }

    @Test func flyingIsBlockedLikeAnyOtherMove() {
        // Quân xanh ở ô 8 chắn giữa quân đỏ (ô 3) và ô cửa chuồng (ô 13): không bay qua được.
        let blocked = makeState(horses: [.red: [.track(3)], .green: [.track(8)]])
        #expect(MoveValidator.resolve(.fly, in: blocked, horse: HorseID(.red, 0), dice: [1]) == nil)
        // Quân mình chắn đường cũng vậy.
        let ownBlocker = makeState(horses: [.red: [.track(3), .track(8)]])
        #expect(MoveValidator.resolve(.fly, in: ownBlocker, horse: HorseID(.red, 0), dice: [1]) == nil)
        #expect(MoveValidator.resolve(.fly, in: ownBlocker, horse: HorseID(.red, 1), dice: [1])?.to == .track(13))
        // Đường trống, ô đáp có quân mình: không bay được. Ô đáp có quân đối phương: đá quân đó.
        let landing = makeState(horses: [.red: [.track(3), .track(13)], .green: [.track(27)]])
        #expect(MoveValidator.resolve(.fly, in: landing, horse: HorseID(.red, 0), dice: [1]) == nil)
        #expect(MoveValidator.resolve(.fly, in: landing, horse: HorseID(.red, 1), dice: [1])?.captures == [HorseID(.green, 0)])
        // Quân đang chờ ở ô xuất phát của màu khác (ô 14) nằm ngoài đường chạy nên không cản nước bay từ ô 13 tới ô 27.
        let waiting = makeState([.red, .blue], horses: [.red: [.track(13)], .blue: [.track(14)]])
        #expect(MoveValidator.resolve(.fly, in: waiting, horse: HorseID(.red, 0), dice: [1])?.to == .track(27))
    }

    @Test func flyingCanBeSwitchedOffInTheRules() {
        var rules = RulesConfiguration.traditional
        rules.flyOnOne = false
        let state = makeState(rules: rules, horses: [.red: [.track(3)]])
        #expect(MoveValidator.options(in: state, horse: HorseID(.red, 0), dice: [1]).map(\.kind) == [.advance])
    }

    @Test func flyingWorksWithASingleDieAndEndsTheTurn() throws {
        var engine = try rolled([1], rules: .traditional, horses: [.red: [.track(3)], .green: [.track(13)]])
        #expect(engine.legalMoves.count == 2)
        let events = try engine.apply(.move(horse: HorseID(.red, 0), use: .fly), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(13))
        #expect(engine.state.player(.green)!.horses[0] == .stable)
        #expect(events.last == .turnChanged(to: .green))
        #expect(engine.state.remainingDice.isEmpty)
    }

    @Test func flyingWithoutAOneIsRejected() throws {
        var engine = try rolled([4], rules: .traditional, horses: [.red: [.track(3)]])
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.red, 0), use: .fly), by: .red) }
    }
}

@Suite("Chế độ nhanh: hai xúc xắc")
struct SpeedModeTests {
    @Test func theNumberOfDiceMustMatchTheRules() {
        var speed = GameEngine(colors: [.red, .green], rules: speedRules)
        #expect(throws: GameError.invalidDiceValue) { try speed.apply(.roll(value: 3), by: .red) }
        #expect(throws: GameError.invalidDiceValue) { try speed.apply(.roll(value: 3, second: 7), by: .red) }
        var normal = GameEngine(colors: [.red, .green])
        #expect(throws: GameError.invalidDiceValue) { try normal.apply(.roll(value: 3, second: 4), by: .red) }
        var rules = speedRules
        rules.diceCount = 3
        #expect(!rules.isValid())
    }

    @Test func eachDieCanBeUsedForASeparateMoveInEitherOrder() throws {
        var engine = try rolled([3, 5], horses: [.red: [.track(0), .track(20)]])
        #expect(engine.state.remainingDice == [3, 5])
        // Dùng viên thứ hai (5) trước cho quân #1.
        try engine.apply(.move(horse: HorseID(.red, 1), use: .die(index: 1)), by: .red)
        #expect(engine.state.player(.red)!.horses[1] == .track(25))
        #expect(engine.state.remainingDice == [3])
        #expect(engine.state.phase == .awaitingMove(roll: 3))
        #expect(engine.state.currentColor == .red)
        // Viên còn lại (3) cho quân #0.
        let events = try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(3))
        #expect(events.last == .turnChanged(to: .green))
    }

    @Test func bothDiceCanGoToTheSameHorse() throws {
        var engine = try rolled([3, 5], horses: [.red: [.track(0)]])
        try engine.apply(.move(horse: HorseID(.red, 0), use: .die(index: 0)), by: .red)
        try engine.apply(.move(horse: HorseID(.red, 0), use: .die(index: 0)), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(8))
        #expect(engine.state.currentColor == .green)
    }

    @Test func theSumMovesOneHorseInASingleJump() throws {
        var engine = try rolled([3, 5], horses: [.red: [.track(0)], .green: [.track(8)]])
        let sum = try #require(engine.legalMoves.first { $0.use == .sum })
        #expect(sum.roll == 8)
        #expect(sum.path.count == 8)
        let events = try engine.apply(sum.action, by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(8))
        #expect(engine.state.player(.green)!.horses[0] == .stable)
        #expect(engine.state.remainingDice.isEmpty)
        #expect(events.last == .turnChanged(to: .green))
    }

    @Test func theSumIsBlockedByAnyHorseOnTheWay() throws {
        // Quân xanh ở ô 4 chắn đường: cộng 8 không đi được, và viên 5 cũng bị chắn; viên 3 thì đi được.
        let engine = try rolled([3, 5], horses: [.red: [.track(0)], .green: [.track(4)]])
        #expect(engine.legalMoves.map(\.use) == [.die(index: 0)])
    }

    @Test func theSumNeverReleasesAHorseButASingleSixDoes() throws {
        // 3 + 3 = 6 nhưng không viên nào ra 6: không ra quân được, và vì ra đôi nên được đổ lại.
        var doubles = GameEngine(colors: [.red, .green], rules: speedRules)
        let events = try doubles.apply(.roll(value: 3, second: 3), by: .red)
        #expect(events == [.rolled(player: .red, value: 3, second: 3), .noLegalMove(player: .red, roll: 3), .bonusTurn(player: .red)])

        var engine = try rolled([6, 4], horses: [:])
        #expect(Set(engine.legalMoves.map(\.kind)) == [.release])
        try engine.apply(.move(horse: HorseID(.red, 2), use: .die(index: 0)), by: .red)
        // Viên còn lại (4) đi luôn quân vừa ra.
        #expect(engine.state.remainingDice == [4])
        try engine.apply(.move(horse: HorseID(.red, 2)), by: .red)
        #expect(engine.state.player(.red)!.horses[2] == .track(4))
        // 6 và 4 không phải đôi: hết lượt, không đổ thêm.
        #expect(engine.state.currentColor == .green)
    }

    @Test func aDieWithNoLegalMoveIsForfeited() throws {
        // Quân duy nhất cách cửa chuồng 3 bước: viên 3 đi được, viên 5 sau đó không còn nước nào.
        var engine = try rolled([3, 5], horses: [.red: [sq(Board.stepsToMouth - 3, .red), .home(6), .home(5), .home(4)]])
        let events = try engine.apply(.move(horse: HorseID(.red, 0), use: .die(index: 0)), by: .red)
        #expect(events.contains(.noLegalMove(player: .red, roll: 5)))
        #expect(events.last == .turnChanged(to: .green))
        #expect(engine.state.remainingDice.isEmpty)
    }

    @Test func onlyDoublesGrantAnotherRoll() throws {
        var six = try rolled([6, 2], horses: [.red: [.track(0)]])
        try six.apply(six.legalMoves.first { $0.use == .sum }!.action, by: .red)
        #expect(six.state.currentColor == .green)

        var doubles = try rolled([4, 4], horses: [.red: [.track(0)]])
        #expect(doubles.legalMoves.map(\.use) == [.die(index: 0), .sum])
        let events = try doubles.apply(.move(horse: HorseID(.red, 0), use: .sum), by: .red)
        #expect(events.last == .bonusTurn(player: .red))
        #expect(doubles.state.currentColor == .red)
        #expect(doubles.state.phase == .awaitingRoll)
    }

    @Test func consecutiveDoublesRespectTheBonusLimit() throws {
        var rules = speedRules
        rules.maxConsecutiveBonusRolls = 3
        var engine = GameEngine(state: makeState(rules: rules, horses: [.red: [.track(0)]]))
        for _ in 0..<2 {
            try engine.apply(.roll(value: 2, second: 2), by: .red)
            try engine.apply(.move(horse: HorseID(.red, 0), use: .sum), by: .red)
        }
        let events = try engine.apply(.roll(value: 5, second: 5), by: .red)
        #expect(events == [.rolled(player: .red, value: 5, second: 5), .bonusLimitReached(player: .red), .turnChanged(to: .green)])
        #expect(engine.state.player(.red)!.horses[0] == .track(8))
    }

    @Test func aOneAmongTheTwoDiceCanFlyAndLeavesTheOtherDie() throws {
        var engine = try rolled([4, 1], horses: [.red: [.track(3)]])
        #expect(Set(engine.legalMoves.map(\.use)) == [.die(index: 0), .die(index: 1), .sum, .fly])
        try engine.apply(.move(horse: HorseID(.red, 0), use: .fly), by: .red)
        #expect(engine.state.player(.red)!.horses[0] == .track(13))
        #expect(engine.state.remainingDice == [4])
        try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        // Từ ô 13 đi 4 bước: nhảy qua ô 14 (ô xuất phát của Xanh dương), tới ô 18.
        #expect(engine.state.player(.red)!.horses[0] == .track(18))
    }

    @Test func theSumNeverCountsForTheHomeColumn() throws {
        // Ở cửa chuồng với 2 và 3: lên bậc 2 hoặc bậc 3; tổng 5 không được tính.
        let atGate = try rolled([2, 3], horses: [.red: [sq(Board.stepsToMouth, .red)]])
        #expect(Set(atGate.legalMoves.map(\.to)) == [.home(2), .home(3)])
        #expect(!atGate.legalMoves.contains { $0.use == .sum })
        // Trong cột: từ bậc 3 phải có một viên ra đúng 4; 1 + 3 = 4 không lên được.
        let needsFour = try rolled([1, 3], horses: [.red: [.home(3)], .green: [.track(30)]])
        #expect(!needsFour.legalMoves.contains { $0.horse == HorseID(.red, 0) })
        // Có viên 4 thì lên bậc 4, rồi viên 5 lên tiếp bậc 5: từng bậc một, mỗi bậc một viên đúng số.
        var climbs = try rolled([4, 5], horses: [.red: [.home(3)]])
        #expect(climbs.legalMoves.map(\.to) == [.home(4)])
        try climbs.apply(climbs.legalMoves[0].action, by: .red)
        #expect(climbs.legalMoves.map(\.to) == [.home(5)])
        // Trên đường chạy thì tổng vẫn dùng được như cũ.
        let onTrack = try rolled([2, 3], horses: [.red: [.track(20)]])
        #expect(onTrack.legalMoves.contains { $0.use == .sum })
        // Luật kiểu Ludo (đi theo số chấm) vẫn cộng được vào cột đích.
        var ludo = RulesConfiguration.modern
        ludo.diceCount = 2
        let pips = try rolled([2, 3], rules: ludo, horses: [.red: [sq(Board.stepsToMouth, .red)]])
        let ludoSum = pips.legalMoves.first { $0.use == .sum }
        #expect(ludoSum?.to == .home(5))
    }

    @Test func winningWithTheFirstDieEndsTheGameImmediately() throws {
        var engine = try rolled([3, 5], horses: [.red: [.home(6), .home(5), .home(4), .home(2)]])
        let events = try engine.apply(.move(horse: HorseID(.red, 3), use: .die(index: 0)), by: .red)
        #expect(events.last == .gameOver(winner: .red))
        #expect(engine.state.remainingDice.isEmpty)
        #expect(throws: GameError.gameOver) { try engine.apply(.move(horse: HorseID(.red, 3)), by: .red) }
    }

    @Test func usingADieThatIsNotThereIsRejectedAndChangesNothing() throws {
        var engine = try rolled([3, 5], horses: [.red: [.track(0)]])
        let before = engine.state
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.red, 0), use: .die(index: 2)), by: .red) }
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.red, 0), use: .fly), by: .red) }
        #expect(engine.state == before)
        var single = try rolled([3], rules: .traditional, horses: [.red: [.track(0)]])
        #expect(throws: GameError.illegalMove) { try single.apply(.move(horse: HorseID(.red, 0), use: .sum), by: .red) }
        #expect(throws: GameError.illegalMove) { try single.apply(.move(horse: HorseID(.red, 0), use: .die(index: 1)), by: .red) }
    }

    @Test func legalMovesAndTheEngineAgreeOnEveryOption() throws {
        let horses: [PlayerColor: [HorsePosition]] = [.red: [.track(0), .track(9), sq(Board.stepsToMouth, .red), .stable], .green: [.track(5), .track(13)]]
        for first in 1...6 {
            for second in 1...6 {
                let engine = try? rolled([first, second], horses: horses)
                guard let engine, case .awaitingMove = engine.state.phase else { continue }
                let legal = Set(engine.legalMoves.map { "\($0.horse)-\($0.use)" })
                for index in 0..<4 {
                    for use in [DiceUse.die(index: 0), .die(index: 1), .sum, .fly] {
                        var trial = engine
                        let accepted = (try? trial.apply(.move(horse: HorseID(.red, index), use: use), by: .red)) != nil
                        // Hai viên giống nhau: viên thứ hai là cùng một nước với viên thứ nhất.
                        let listed = legal.contains("\(HorseID(.red, index))-\(use)")
                            || (first == second && use == .die(index: 1) && legal.contains("\(HorseID(.red, index))-\(DiceUse.die(index: 0))"))
                        #expect(accepted == listed, "\(first),\(second) quân \(index) \(use)")
                    }
                }
            }
        }
    }

    @Test(arguments: [RulesConfiguration.traditional, .modern], [2, 3, 4])
    func randomSpeedGamesAlwaysFinish(base: RulesConfiguration, playerCount: Int) throws {
        var rules = base
        rules.diceCount = 2
        for seed in 0..<15 {
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
                    try engine.apply(engine.legalMoves.randomElement(using: &generator)!.action, by: color)
                }
                #expect(engine.state.remainingDice.count <= 2)
            }
            #expect(engine.state.player(engine.state.winner!)!.hasWon)
        }
    }
}
