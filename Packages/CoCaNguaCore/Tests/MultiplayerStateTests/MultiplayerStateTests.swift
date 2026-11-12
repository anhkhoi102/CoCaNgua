import Foundation
import GameCore
import OnlineCore
import Testing

@Test func roomPlanSeatsHostFirstAndFillsEmptySeatsWithBots() throws {
    let host = RoomPlan.Member(playerID: "h", name: "Chủ")
    let guests = [RoomPlan.Member(playerID: "z", name: "Z"), RoomPlan.Member(playerID: "a", name: "A")]
    // Phòng 4 chỗ, mới một khách vào: hai chỗ còn lại là bot.
    let oneGuest = RoomPlan.make(host: host, guests: [guests[0]], seatCount: 4, rules: .traditional) { "Máy \($0)" }
    #expect(oneGuest.isValid)
    #expect(oneGuest.seats.map(\.playerID) == ["h", "z", nil, nil])
    #expect(oneGuest.seats.map(\.name) == ["Chủ", "Z", "Máy 1", "Máy 2"])
    #expect(oneGuest.colors == PlayerColor.allCases)
    // Khách được xếp theo định danh, không theo thứ tự vào, để mọi máy ra cùng một kết quả.
    let two = RoomPlan.make(host: host, guests: guests, seatCount: 3, rules: .traditional) { "Máy \($0)" }
    #expect(two.seats.map(\.playerID) == ["h", "a", "z"])
    // Nhiều khách hơn số chỗ thì chỉ lấy đủ chỗ.
    let full = RoomPlan.make(host: host, guests: guests, seatCount: 2, rules: .traditional) { "Máy \($0)" }
    #expect(full.seats.map(\.playerID) == ["h", "a"])

    // Quyền đi quân: mỗi người đi màu của mình, chủ phòng đi cho bot và cho người đã rời.
    #expect(oneGuest.mayAct(sender: "z", for: .blue))
    #expect(!oneGuest.mayAct(sender: "z", for: .red))
    #expect(!oneGuest.mayAct(sender: "z", for: .green))
    #expect(oneGuest.mayAct(sender: "h", for: .green))
    #expect(!oneGuest.mayAct(sender: "h", for: .blue))
    #expect(oneGuest.mayAct(sender: "h", for: .blue, departed: ["z"]))

    // Tin nhắn mã hoá và giải mã lại nguyên vẹn; dữ liệu rác bị từ chối.
    for message in [RoomMessage.hello(isHost: true), .start(oneGuest), .actions(from: 3, bytes: Data([6, 16, 2]))] {
        #expect(RoomMessage.decode(try message.encoded()) == message)
    }
    #expect(RoomMessage.decode(Data([1, 2, 3])) == nil)
    var broken = oneGuest
    broken.seats[1].color = .red
    #expect(!broken.isValid)
}

@Test func roomCodesCarryThePlayerCountAndRoundTrip() {
    var generator = SystemRandomNumberGenerator()
    for count in 2...4 {
        for _ in 0..<200 {
            let code = RoomCode.generate(playerCount: count, using: &generator)
            #expect(code.text.count == RoomCode.length)
            #expect(code.playerCount == count)
            #expect(RoomCode(code.text) == code)
        }
    }
    // Người chơi có thể gõ kèm khoảng trắng hoặc gạch nối.
    #expect(RoomCode(" 312 345 ")?.group == 312_345)
    #expect(RoomCode("3-12345")?.playerCount == 3)
    // Mã sai: thiếu số, có chữ, hoặc chữ số đầu không phải số người chơi hợp lệ.
    for bad in ["", "12345", "1234567", "31234a", "112345", "512345", "012345"] {
        #expect(RoomCode(bad) == nil)
    }
}

/// Chơi `steps` hành động ngẫu nhiên (hoặc tới hết ván) và ghi lại nhật ký.
func playRandom(colors: [PlayerColor], rules: RulesConfiguration = .traditional, seed: UInt64, steps: Int = .max) throws -> (GameEngine, ActionLog) {
    var generator = SeededGenerator(seed: seed)
    var engine = GameEngine(colors: colors, rules: rules)
    var log = ActionLog()
    var done = 0
    while !engine.state.isFinished, done < steps {
        let color = engine.state.currentColor
        let action: GameAction = engine.state.phase == .awaitingRoll
            ? GameEngine.randomRoll(rules: rules, using: &generator)
            : engine.legalMoves.randomElement(using: &generator)!.action
        try engine.apply(action, by: color)
        log.append(action, by: color)
        done += 1
    }
    return (engine, log)
}

func matchData(_ count: Int, log: ActionLog = ActionLog(), rules: RulesConfiguration = .traditional) -> OnlineMatchData {
    var data = OnlineMatchData(playerCount: count, rules: rules)
    data.actionLog = log
    return data
}

@Suite("Nhật ký hành động")
struct ActionLogTests {
    @Test(arguments: [2, 3, 4])
    func replayReproducesTheLiveGameExactly(playerCount: Int) throws {
        let colors = GameRules.defaultColors(playerCount: playerCount)
        let (engine, log) = try playRandom(colors: colors, seed: UInt64(playerCount))
        let replayed = try log.replay(colors: colors, rules: .traditional)
        #expect(replayed.engine.state == engine.state)
        #expect(replayed.engine.state.winner != nil)
        #expect(replayed.actions.count == log.count)
        #expect(engine.state.actionCount == log.count)
    }

    @Test(arguments: [2, 4])
    func speedModeGamesWithSumsAndFlightsReplayExactly(playerCount: Int) throws {
        var rules = RulesConfiguration.traditional
        rules.diceCount = 2
        let colors = GameRules.defaultColors(playerCount: playerCount)
        for seed in 0..<8 {
            let (engine, log) = try playRandom(colors: colors, rules: rules, seed: UInt64(seed))
            let replayed = try log.replay(colors: colors, rules: rules)
            #expect(replayed.engine.state == engine.state)
            #expect(replayed.actions.contains { if case .move(_, .sum) = $0.action { true } else { false } })
            #expect(replayed.actions.contains { if case .move(_, .fly) = $0.action { true } else { false } })
            #expect(replayed.actions.contains { if case .move(_, .die(index: 1)) = $0.action { true } else { false } })
            let snapshot = try OnlineMatchValidator.load(try matchData(playerCount, log: log, rules: rules).encoded(), playerCount: playerCount, newMatchRules: .traditional)
            #expect(snapshot.state == engine.state)
        }
    }

    @Test func everyActionKindHasItsOwnByte() {
        var log = ActionLog()
        log.append(.roll(value: 4), by: .red)
        log.append(.roll(value: 1, second: 1), by: .red)
        log.append(.roll(value: 6, second: 6), by: .red)
        log.append(.move(horse: HorseID(.red, 0)), by: .red)
        log.append(.move(horse: HorseID(.red, 3), use: .die(index: 1)), by: .red)
        log.append(.move(horse: HorseID(.red, 2), use: .sum), by: .red)
        log.append(.move(horse: HorseID(.red, 1), use: .fly), by: .red)
        log.append(.resign, by: .yellow)
        #expect(log.bytes == [4, 64, 99, 16, 23, 26, 29, 35])
    }

    @Test func twoDiceRollsAreRejectedInASingleDieMatchAndViceVersa() {
        var speed = RulesConfiguration.traditional
        speed.diceCount = 2
        #expect(throws: OnlineMatchError.illegalAction(index: 0)) { try ActionLog(bytes: [70]).replay(colors: [.red, .green], rules: .traditional) }
        #expect(throws: OnlineMatchError.illegalAction(index: 0)) { try ActionLog(bytes: [3]).replay(colors: [.red, .green], rules: speed) }
    }

    @Test func oneBytePerActionKeepsAFullMatchSmall() throws {
        for seed in 0..<10 {
            let (_, log) = try playRandom(colors: PlayerColor.allCases, seed: UInt64(seed))
            let encoded = try matchData(4, log: log).encoded()
            // Giới hạn matchData của Game Center là 64 KB; một ván dài vẫn phải còn rất xa mức đó.
            #expect(encoded.count < 16_000, "ván \(seed): \(encoded.count) byte cho \(log.count) hành động")
        }
    }

    @Test func resignationsAreRecordedWithTheirColourEvenOutOfTurn() throws {
        var engine = GameEngine(colors: PlayerColor.allCases)
        var log = ActionLog()
        try engine.apply(.resign, by: .green)
        log.append(.resign, by: .green)
        try engine.apply(.roll(value: 3), by: .red)
        log.append(.roll(value: 3), by: .red)
        let replayed = try log.replay(colors: PlayerColor.allCases, rules: .traditional)
        #expect(replayed.actions[0] == RecordedAction(color: .green, action: .resign))
        #expect(replayed.engine.state == engine.state)
        #expect(log.bytes == [34, 3])
    }

    @Test(arguments: [[UInt8(0)], [7], [15], [36], [63], [100], [200], [16], [3, 3, 3, 16], [6, 16, 6, 17], [32, 32], [3, 20], [3, 24], [3, 28]])
    func illegalOrOutOfOrderBytesAreRejected(bytes: [UInt8]) {
        #expect(throws: OnlineMatchError.self) {
            try ActionLog(bytes: bytes).replay(colors: [.red, .green], rules: .traditional)
        }
    }

    @Test func theIndexOfTheFirstBadActionIsReported() {
        // Đỏ đổ 6, ra quân #0, đổ 2, rồi "đi" quân #1 còn trong chuồng.
        #expect(throws: OnlineMatchError.illegalAction(index: 3)) {
            try ActionLog(bytes: [6, 16, 2, 17]).replay(colors: [.red, .green], rules: .traditional)
        }
    }

    @Test func nothingCanFollowTheEndOfTheGame() throws {
        let (_, log) = try playRandom(colors: [.red, .green], seed: 9)
        #expect(throws: OnlineMatchError.illegalAction(index: log.count)) {
            try ActionLog(bytes: log.bytes + [3]).replay(colors: [.red, .green], rules: .traditional)
        }
    }

    @Test func prefixCheckOnlyAllowsAppending() throws {
        let (_, log) = try playRandom(colors: [.red, .green], seed: 2, steps: 40)
        let longer = ActionLog(bytes: log.bytes + [3])
        #expect(log.isPrefix(of: longer))
        #expect(log.isPrefix(of: log))
        #expect(!longer.isPrefix(of: log))
        var edited = log.bytes
        edited[5] = edited[5] == 1 ? 2 : 1
        #expect(!log.isPrefix(of: ActionLog(bytes: edited + [3])))
        #expect(ActionLog().isPrefix(of: log))
    }
}

@Suite("Dữ liệu trận")
struct OnlineMatchDataTests {
    @Test func emptyDataStartsANewMatchWithTheCreatorsRules() throws {
        for raw in [nil, Data()] as [Data?] {
            let snapshot = try OnlineMatchValidator.load(raw, playerCount: 3, newMatchRules: .modern)
            #expect(snapshot.data.rules == .modern)
            #expect(snapshot.data.seatColors == [.red, .blue, .green])
            #expect(snapshot.state.actionCount == 0)
            #expect(snapshot.seatToMove == 0)
        }
    }

    @Test(arguments: [2, 3, 4])
    func encodedDataLoadsBackToTheSameGame(playerCount: Int) throws {
        let colors = GameRules.defaultColors(playerCount: playerCount)
        let (engine, log) = try playRandom(colors: colors, rules: .modern, seed: 4, steps: 120)
        let raw = try matchData(playerCount, log: log, rules: .modern).encoded()
        // Luật của máy đang đọc không được ghi đè luật của trận.
        let snapshot = try OnlineMatchValidator.load(raw, playerCount: playerCount, newMatchRules: .traditional)
        #expect(snapshot.state == engine.state)
        #expect(snapshot.data.rules == .modern)
        #expect(snapshot.log == log)
        #expect(snapshot.seatToMove == colors.firstIndex(of: engine.state.currentColor))
    }

    @Test func seatsMapToColoursByParticipantOrder() throws {
        let two = try OnlineMatchValidator.load(nil, playerCount: 2, newMatchRules: .traditional)
        #expect(two.seat(of: .red) == 0)
        #expect(two.seat(of: .green) == 1)
        #expect(two.seat(of: .blue) == nil)
        let four = try OnlineMatchValidator.load(nil, playerCount: 4, newMatchRules: .traditional)
        #expect(PlayerColor.allCases.map { four.seat(of: $0) } == [0, 1, 2, 3])
    }

    @Test func corruptDataIsRejected() {
        for text in ["", "{", "không phải json", "[]", "{\"format\":1}", "{\"format\":0,\"log\":\"\"}", "{\"format\":\"1\"}"] where !text.isEmpty {
            #expect(throws: OnlineMatchError.corrupt) {
                try OnlineMatchValidator.load(Data(text.utf8), playerCount: 2, newMatchRules: .traditional)
            }
        }
    }

    @Test func dataFromANewerAppVersionIsRefusedNotMisread() throws {
        var data = matchData(2)
        data.format = OnlineMatchData.currentFormat + 1
        #expect(OnlineMatchData.currentFormat == 4)
        let raw = try data.encoded()
        #expect(throws: OnlineMatchError.newerFormat(OnlineMatchData.currentFormat + 1)) {
            try OnlineMatchValidator.load(raw, playerCount: 2, newMatchRules: .traditional)
        }
    }

    @Test func seatAndRuleTamperingIsRejected() throws {
        var duplicate = matchData(2)
        duplicate.seatColors = [.red, .red]
        #expect(throws: OnlineMatchError.invalidSeats) {
            try OnlineMatchValidator.load(try duplicate.encoded(), playerCount: 2, newMatchRules: .traditional)
        }
        #expect(throws: OnlineMatchError.invalidSeats) {
            try OnlineMatchValidator.load(try matchData(3).encoded(), playerCount: 2, newMatchRules: .traditional)
        }
        var rules = matchData(2)
        rules.rules.releaseValues = []
        #expect(throws: OnlineMatchError.invalidRules) {
            try OnlineMatchValidator.load(try rules.encoded(), playerCount: 2, newMatchRules: .traditional)
        }
        #expect(throws: OnlineMatchError.invalidSeats) {
            try OnlineMatchValidator.load(nil, playerCount: 5, newMatchRules: .traditional)
        }
    }

    @Test func anIllegalMoveInsideTheLogRejectsTheWholeUpdate() throws {
        var data = matchData(2)
        data.actionLog = ActionLog(bytes: [6, 16, 2, 17])
        #expect(throws: OnlineMatchError.illegalAction(index: 3)) {
            try OnlineMatchValidator.load(try data.encoded(), playerCount: 2, newMatchRules: .traditional)
        }
    }

    @Test func oversizedDataIsRefusedBeforeSending() throws {
        let (_, log) = try playRandom(colors: [.red, .green], seed: 1)
        #expect(throws: OnlineMatchError.tooLarge) { try matchData(2, log: log).encoded(maximumSize: 64) }
        #expect(try matchData(2, log: log).encoded(maximumSize: 65_536).count > 64)
    }
}

@Suite("Kiểm tra bản cập nhật")
struct OnlineMatchValidationTests {
    private func snapshot(_ count: Int, bytes: [UInt8]) throws -> OnlineMatchSnapshot {
        try OnlineMatchValidator.load(try matchData(count, log: ActionLog(bytes: bytes)).encoded(), playerCount: count, newMatchRules: .traditional)
    }

    @Test func aNormalTurnIsAccepted() throws {
        // Đỏ đổ 3 (không có nước), lượt sang Xanh lá ở chỗ ngồi 1.
        let incoming = try snapshot(2, bytes: [3])
        #expect(incoming.seatToMove == 1)
        try OnlineMatchValidator.validate(incoming, known: ActionLog(), currentSeat: 1)
        try OnlineMatchValidator.validate(incoming, known: nil, currentSeat: 1)
    }

    @Test func rewritingHistoryIsDetected() throws {
        let known = ActionLog(bytes: [3, 2])
        // Kẻ gian đổi lần đổ đầu của mình từ 3 thành 6 rồi ra quân.
        let forged = try snapshot(2, bytes: [6, 16, 2])
        #expect(throws: OnlineMatchError.historyRewritten) {
            try OnlineMatchValidator.validate(forged, known: known, currentSeat: forged.seatToMove)
        }
        // Xoá bớt hành động cũng bị phát hiện.
        let truncated = try snapshot(2, bytes: [3])
        #expect(throws: OnlineMatchError.historyRewritten) {
            try OnlineMatchValidator.validate(truncated, known: known, currentSeat: truncated.seatToMove)
        }
    }

    @Test func passingTheTurnToTheWrongPlayerIsDetected() throws {
        // Sau khi Đỏ đổ 3, ván tới lượt Xanh lá (chỗ 1); Game Center lại báo chỗ 0 giữ lượt.
        let incoming = try snapshot(2, bytes: [3])
        #expect(throws: OnlineMatchError.turnMismatch) {
            try OnlineMatchValidator.validate(incoming, known: nil, currentSeat: 0)
        }
        // Người chơi kết thúc lượt giữa chừng (đã đổ 6 nhưng chưa đi) cũng là sai.
        let midTurn = try snapshot(2, bytes: [6])
        #expect(midTurn.seatToMove == 0)
        #expect(throws: OnlineMatchError.turnMismatch) {
            try OnlineMatchValidator.validate(midTurn, known: nil, currentSeat: 1)
        }
    }

    @Test func aPlayerWhoLeftIsResignedByWhoeverHoldsTheTurn() throws {
        // 3 người; chỗ 1 (Xanh dương) hết hạn lượt nên Game Center chuyển lượt cho chỗ 2, nhưng ván vẫn ghi tới lượt Xanh dương.
        let incoming = try snapshot(3, bytes: [3])
        #expect(incoming.seatToMove == 1)
        try OnlineMatchValidator.validate(incoming, known: nil, currentSeat: 2, outOfPlaySeats: [1])
        let fixes = OnlineMatchValidator.reconciliation(outOfPlaySeats: [1], in: incoming)
        #expect(fixes == [RecordedAction(color: .blue, action: .resign)])

        var engine = incoming.engine
        var log = incoming.log
        for fix in fixes {
            try engine.apply(fix.action, by: fix.color)
            log.append(fix.action, by: fix.color)
        }
        #expect(engine.state.currentColor == .green)
        let after = try OnlineMatchValidator.load(try matchData(3, log: log).encoded(), playerCount: 3, newMatchRules: .traditional)
        #expect(after.seatToMove == 2)
        // Đã xử rồi thì không xử lại.
        #expect(OnlineMatchValidator.reconciliation(outOfPlaySeats: [1], in: after).isEmpty)
    }

    @Test func reconciliationEndsATwoPlayerMatchWhenTheOpponentLeaves() throws {
        let incoming = try snapshot(2, bytes: [3])
        var engine = incoming.engine
        for fix in OnlineMatchValidator.reconciliation(outOfPlaySeats: [1, 7], in: incoming) {
            try engine.apply(fix.action, by: fix.color)
        }
        #expect(engine.state.winner == .red)
        let finished = try snapshot(2, bytes: [3, 34])
        #expect(finished.seatToMove == nil)
        #expect(OnlineMatchValidator.reconciliation(outOfPlaySeats: [0], in: finished).isEmpty)
        // Ván đã xong thì Game Center báo ai giữ lượt cũng không còn ý nghĩa.
        try OnlineMatchValidator.validate(finished, known: ActionLog(bytes: [3]), currentSeat: 0)
    }

    /// Mô phỏng nhiều máy chuyền dữ liệu cho nhau qua từng lượt: máy nào cũng kiểm tra, không máy nào lệch.
    @Test(arguments: [2, 3, 4])
    func aWholeMatchPassedBetweenDevicesStaysConsistent(playerCount: Int) throws {
        var generator = SeededGenerator(seed: UInt64(40 + playerCount))
        var raw: Data? = nil
        var known = [ActionLog?](repeating: nil, count: playerCount)
        var currentSeat = 0
        var turns = 0
        while true {
            turns += 1
            try #require(turns < 20_000)
            // Máy đang giữ lượt nhận dữ liệu, kiểm tra, rồi chơi hết lượt của mình.
            let incoming = try OnlineMatchValidator.load(raw, playerCount: playerCount, newMatchRules: .traditional)
            try OnlineMatchValidator.validate(incoming, known: known[currentSeat], currentSeat: currentSeat)
            if incoming.state.isFinished { break }
            var engine = incoming.engine
            var log = incoming.log
            let color = incoming.data.seatColors[currentSeat]
            while !engine.state.isFinished, engine.state.currentColor == color {
                let action: GameAction = engine.state.phase == .awaitingRoll
                    ? GameEngine.randomRoll(rules: incoming.data.rules, using: &generator)
                    : engine.legalMoves.randomElement(using: &generator)!.action
                try engine.apply(action, by: color)
                log.append(action, by: color)
            }
            var data = incoming.data
            data.actionLog = log
            raw = try data.encoded(maximumSize: 65_536)
            known[currentSeat] = log
            currentSeat = engine.state.isFinished ? currentSeat : data.seatColors.firstIndex(of: engine.state.currentColor)!
        }
        let final = try OnlineMatchValidator.load(raw, playerCount: playerCount, newMatchRules: .traditional)
        #expect(final.state.winner != nil)
        for seat in 0..<playerCount { try OnlineMatchValidator.validate(final, known: known[seat], currentSeat: nil) }
    }
}
