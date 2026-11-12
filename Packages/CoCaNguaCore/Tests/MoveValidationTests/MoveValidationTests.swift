import Testing
@testable import GameCore

@Suite("Từ chối hành động không hợp lệ")
struct MoveValidationTests {
    @Test func rollingOutOfTurnIsRejected() {
        var engine = GameEngine(colors: [.red, .green])
        #expect(throws: GameError.notYourTurn) { try engine.apply(.roll(value: 6), by: .green) }
    }

    @Test func movingBeforeRollingIsRejected() {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)]]))
        #expect(throws: GameError.wrongPhase) { try engine.apply(.move(horse: HorseID(.red, 0)), by: .red) }
    }

    @Test func rollingTwiceBeforeMovingIsRejected() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)]]))
        try engine.apply(.roll(value: 2), by: .red)
        #expect(throws: GameError.wrongPhase) { try engine.apply(.roll(value: 6), by: .red) }
    }

    @Test(arguments: [0, 7, -1, 100])
    func diceValuesOutsideOneToSixAreRejected(value: Int) {
        var engine = GameEngine(colors: [.red, .green])
        #expect(throws: GameError.invalidDiceValue) { try engine.apply(.roll(value: value), by: .red) }
    }

    @Test func movingAHorseThatCannotMoveIsRejected() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)]]))
        try engine.apply(.roll(value: 2), by: .red)
        // Quân #1 còn trong chuồng, đổ 2 không ra quân được.
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.red, 1)), by: .red) }
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.red, 9)), by: .red) }
    }

    @Test func movingAnOpponentsHorseIsRejected() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)], .green: [.track(30)]]))
        try engine.apply(.roll(value: 2), by: .red)
        #expect(throws: GameError.illegalMove) { try engine.apply(.move(horse: HorseID(.green, 0)), by: .red) }
        #expect(throws: GameError.notYourTurn) { try engine.apply(.move(horse: HorseID(.green, 0)), by: .green) }
    }

    @Test func playersNotInTheMatchAreRejected() {
        var engine = GameEngine(colors: [.red, .green])
        #expect(throws: GameError.unknownPlayer) { try engine.apply(.roll(value: 6), by: .blue) }
    }

    @Test func resignedPlayersCannotAct() throws {
        var engine = GameEngine(colors: [.red, .blue, .green])
        try engine.apply(.resign, by: .blue)
        #expect(throws: GameError.unknownPlayer) { try engine.apply(.resign, by: .blue) }
    }

    @Test func nothingIsAcceptedAfterTheGameEnds() throws {
        var engine = GameEngine(colors: [.red, .green])
        try engine.apply(.resign, by: .green)
        #expect(engine.state.winner == .red)
        #expect(throws: GameError.gameOver) { try engine.apply(.roll(value: 6), by: .red) }
    }

    @Test func rejectedActionsLeaveTheStateUntouched() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)]]))
        try engine.apply(.roll(value: 2), by: .red)
        let before = engine.state
        _ = try? engine.apply(.move(horse: HorseID(.red, 1)), by: .red)
        _ = try? engine.apply(.roll(value: 3), by: .green)
        #expect(engine.state == before)
    }

    @Test func actionCountIncreasesOncePerAcceptedAction() throws {
        var engine = GameEngine(state: makeState(horses: [.red: [.track(3)]]))
        try engine.apply(.roll(value: 2), by: .red)
        try engine.apply(.move(horse: HorseID(.red, 0)), by: .red)
        #expect(engine.state.actionCount == 2)
    }

    @Test func legalMovesMatchWhatTheEngineAccepts() throws {
        let state = makeState(horses: [.red: [.track(0), .track(4), sq(Board.stepsToMouth, .red), .home(2)], .green: [.track(6)]])
        for roll in 1...6 {
            let legal = Set(MoveValidator.legalMoves(in: state, for: .red, roll: roll).map(\.horse))
            for index in 0..<4 {
                var engine = GameEngine(state: state)
                let horse = HorseID(.red, index)
                guard (try? engine.apply(.roll(value: roll), by: .red)) != nil,
                      case .awaitingMove = engine.state.phase else {
                    #expect(legal.isEmpty)
                    continue
                }
                let accepted = (try? engine.apply(.move(horse: horse), by: .red)) != nil
                #expect(accepted == legal.contains(horse), "đổ \(roll), quân \(horse)")
            }
        }
    }
}
