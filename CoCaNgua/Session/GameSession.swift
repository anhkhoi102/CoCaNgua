import Foundation
import GameCore
import Observation
import OnlineCore

enum SeatController: Equatable, Sendable {
    /// Người chơi ngồi trước máy này.
    case human
    case ai(AIDifficulty)
    /// Người chơi ở máy khác (chơi mạng).
    case remote
}

struct Seat: Identifiable, Equatable, Sendable {
    var color: PlayerColor
    var name: String
    var controller: SeatController
    var id: Int { color.rawValue }
}

struct MatchConfiguration: Sendable {
    var seats: [Seat]
    var rules: RulesConfiguration

    /// Ván chơi đơn: người chơi cầm `humanColor`, đấu với `opponents` máy (1...3) cùng mức độ.
    /// Hai người thì ngồi đối diện; ba người thì hai máy ngồi kế tiếp theo chiều kim đồng hồ.
    static func singlePlayer(humanColor: PlayerColor, opponents: Int, difficulty: AIDifficulty,
                             rules: RulesConfiguration) -> MatchConfiguration {
        let all = PlayerColor.allCases
        let start = all.firstIndex(of: humanColor) ?? 0
        let offsets: [Int] = switch min(max(opponents, 1), 3) {
        case 1: [0, 2]
        case 2: [0, 1, 2]
        default: [0, 1, 2, 3]
        }
        let colors = offsets.map { all[(start + $0) % all.count] }.sorted { $0.rawValue < $1.rawValue }
        var botNumber = 0
        let seats = colors.map { color -> Seat in
            if color == humanColor { return Seat(color: color, name: L("Bạn", "You"), controller: .human) }
            botNumber += 1
            return Seat(color: color, name: L("Máy \(botNumber)", "Bot \(botNumber)"), controller: .ai(difficulty))
        }
        return MatchConfiguration(seats: seats, rules: rules)
    }
}

struct MatchResult: Equatable, Sendable {
    var winner: PlayerColor
    var standings: [PlayerColor]
    var duration: TimeInterval
    var turns: Int
}

/// Cầu nối giữa một ván và dịch vụ chơi mạng. `GameSession` không biết gì về GameKit; nó chỉ gọi giao thức này.
@MainActor
protocol MatchSyncing: AnyObject {
    /// Gửi nhật ký sau khi người chơi ở máy này vừa hành động (hoặc sau khi áp dụng các hành động từ xa).
    /// Chỉ trả về khi đã gửi xong; trả về `false` nếu ván bị huỷ trong lúc chờ.
    func publish(log: ActionLog, state: GameState) async -> Bool
    /// Chờ tới khi có hành động mới sau `count` hành động đã biết. `nil` = ván bị huỷ hoặc dữ liệu không hợp lệ.
    func remoteActions(after count: Int) async -> [RecordedAction]?
    /// Các hành động cần áp dụng ngay trước lượt của người chơi ở máy này (xử bỏ cuộc cho người đã rời trận).
    func pendingActions(after count: Int) -> [RecordedAction]
}

private struct AnyGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator
    mutating func next() -> UInt64 { base.next() }
}

/// Điều phối một ván: nhận thao tác của người chơi, điều khiển máy, nhận hành động từ xa, đổ xúc xắc,
/// gọi `GameEngine`, rồi cho cảnh bàn cờ diễn hoạt kết quả. Không tự quyết định luật.
@MainActor
@Observable
final class GameSession {
    private(set) var configuration: MatchConfiguration
    let scene: BoardScene

    /// Trạng thái hiển thị trên HUD (cập nhật sau khi hoạt ảnh của mỗi hành động chạy xong).
    private(set) var state: GameState
    /// Các mặt xúc xắc đang hiển thị (một viên, hoặc hai viên ở chế độ nhanh).
    private(set) var diceFaces: [Int]
    /// Viên nào của lần đổ này đã được dùng.
    private(set) var diceUsed: [Bool]
    private(set) var diceTilt = 0.0
    private(set) var diceRolling = false
    private(set) var diceOwner: PlayerColor
    private(set) var message = ""
    private(set) var awaitingHumanRoll = false
    private(set) var awaitingHumanMove = false
    private(set) var result: MatchResult?
    /// Ghi chú kết nối khi chơi mạng (ví dụ "Đang gửi…", "Đang kết nối lại…").
    var connectionNote: String?
    /// Mã phòng của ván chơi mạng (nếu có), hiện trong ván để chủ phòng đọc cho bạn bè.
    var roomCode: String?
    /// Ván trong phòng chơi trực tiếp: mọi người phải ở trong phòng, rời ra là mất chỗ.
    var isLive = false
    /// Toàn bộ hành động của ván, dùng cho chơi mạng.
    private(set) var log: ActionLog

    private var engine: GameEngine
    private var generator: AnyGenerator
    private let settings: GameSettings
    private let audio = AudioManager.shared
    private let startedAt = Date()
    private weak var sync: MatchSyncing?
    private var loop: Task<Void, Never>?
    private var rollContinuation: CheckedContinuation<Void, Never>?
    private var moveContinuation: CheckedContinuation<Move?, Never>?
    private var lastTurnAnnounced = 0

    var isOnline: Bool { sync != nil }

    init(configuration: MatchConfiguration, settings: GameSettings, initialState: GameState? = nil,
         log: ActionLog = ActionLog(), sync: MatchSyncing? = nil,
         generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.configuration = configuration
        self.settings = settings
        self.generator = AnyGenerator(base: generator)
        self.log = log
        self.sync = sync
        let engine = initialState.map(GameEngine.init(state:))
            ?? GameEngine(colors: configuration.seats.map(\.color), rules: configuration.rules)
        self.engine = engine
        self.state = engine.state
        self.diceOwner = engine.state.currentColor
        let count = configuration.rules.diceCount
        self.diceFaces = engine.state.rolledDice.count == count ? engine.state.rolledDice : Array(repeating: 1, count: count)
        self.diceUsed = Array(repeating: false, count: count)
        self.scene = BoardScene(rules: configuration.rules, pieceStyle: settings.pieceStyle,
                                viewpoint: configuration.seats.first { $0.controller == .human }?.color)
        scene.sync(with: engine.state)
        scene.onMoveChosen = { [weak self] move in self?.humanChose(move) }
        refreshDiceUsage()
    }

    func seat(_ color: PlayerColor) -> Seat {
        configuration.seats.first { $0.color == color } ?? Seat(color: color, name: Theme.name(color), controller: .ai(.easy))
    }

    /// Đổi tên hiển thị của một chỗ ngồi (ví dụ khi đối thủ được ghép vào trận).
    func rename(_ color: PlayerColor, to name: String) {
        guard let index = configuration.seats.firstIndex(where: { $0.color == color }) else { return }
        configuration.seats[index].name = name
    }

    /// Đổi người điều khiển một chỗ ngồi giữa ván (bot của chủ phòng chơi thay người vừa rời phòng).
    func setController(_ controller: SeatController, for color: PlayerColor) {
        guard let index = configuration.seats.firstIndex(where: { $0.color == color }) else { return }
        configuration.seats[index].controller = controller
    }

    var humanColor: PlayerColor? { configuration.seats.first { $0.controller == .human }?.color }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    /// Dừng ván (về menu). An toàn khi gọi nhiều lần.
    func stop() {
        loop?.cancel()
        rollContinuation?.resume()
        rollContinuation = nil
        moveContinuation?.resume(returning: nil)
        moveContinuation = nil
    }

    // MARK: - Thao tác của người chơi

    func humanRoll() {
        guard awaitingHumanRoll, let continuation = rollContinuation else { return }
        rollContinuation = nil
        awaitingHumanRoll = false
        continuation.resume()
    }

    func humanChose(_ move: Move) {
        guard awaitingHumanMove, let continuation = moveContinuation else { return }
        guard engine.legalMoves.contains(move) else {
            audio.play(.uiError)
            return
        }
        moveContinuation = nil
        awaitingHumanMove = false
        audio.play(.uiSelect)
        continuation.resume(returning: move)
    }

    /// Các nước người chơi đang được phép chọn.
    var selectableMoves: [Move] { awaitingHumanMove ? engine.legalMoves : [] }

    // MARK: - Vòng lặp ván

    private func run() async {
        applySettings()
        // Vào lại một ván đã kết thúc (chơi mạng): chỉ hiện kết quả.
        if let winner = engine.state.winner { finish(winner: winner, celebrate: false) }

        while !engine.state.isFinished, !Task.isCancelled {
            let color = engine.state.currentColor
            let seat = seat(color)
            diceOwner = color
            applySettings()

            switch seat.controller {
            case .remote:
                message = L("Đang chờ \(seat.name)…", "Waiting for \(seat.name)…")
                guard let sync, let actions = await sync.remoteActions(after: log.count) else { return }
                for recorded in actions where !Task.isCancelled {
                    guard await perform(recorded, publish: false) else { return }
                }
                // Nếu các hành động vừa nhận làm ván kết thúc hoặc trả lượt về máy này, đồng bộ lại ngay.
                if engine.state.isFinished { _ = await sync.publish(log: log, state: engine.state) }
                continue
            case .human:
                if let sync {
                    for recorded in sync.pendingActions(after: log.count) {
                        guard await perform(recorded, publish: false) else { return }
                    }
                    if engine.state.isFinished {
                        _ = await sync.publish(log: log, state: engine.state)
                        continue
                    }
                    if engine.state.currentColor != color { continue }
                }
                if case .awaitingRoll = engine.state.phase {
                    if lastTurnAnnounced != engine.state.turnNumber { audio.play(.yourTurn) }
                    message = L("Tới lượt bạn — đổ xúc xắc!", "Your turn — roll the dice!")
                    awaitingHumanRoll = true
                    await withCheckedContinuation { rollContinuation = $0 }
                }
            case .ai:
                message = L("\(seat.name) đang đổ xúc xắc…", "\(seat.name) is rolling…")
                await pause(0.55)
            }
            lastTurnAnnounced = engine.state.turnNumber
            if Task.isCancelled { return }

            // Vào lại giữa lượt (chơi mạng): xúc xắc đã đổ rồi thì không đổ lại.
            if case .awaitingRoll = engine.state.phase {
                // Kết quả được quyết định trước; hoạt ảnh xúc xắc chỉ trình bày lại giá trị này.
                let roll = GameEngine.randomRoll(rules: engine.state.rules, using: &generator)
                guard await perform(RecordedAction(color: color, action: roll), publish: seat.controller != .remote) else { return }
            }

            // Đi quân cho tới khi dùng hết các viên xúc xắc của lần đổ này (chế độ nhanh có hai viên).
            while case .awaitingMove = engine.state.phase, engine.state.currentColor == color, !Task.isCancelled {
                let moves = engine.legalMoves
                let chosen: Move
                switch seat.controller {
                case .human:
                    if settings.autoMoveSingleOption, let only = Self.onlyChoice(among: moves) {
                        await pause(0.3)
                        chosen = only
                    } else {
                        message = prompt(for: moves)
                        scene.setSelectable(moves)
                        // Chỉ một quân đi được nhưng có nhiều cách đi: mở sẵn các ô đích của quân đó.
                        if Set(moves.map(\.horse)).count == 1 { scene.focus(moves[0].horse) }
                        awaitingHumanMove = true
                        let picked = await withCheckedContinuation { moveContinuation = $0 }
                        scene.setSelectable([])
                        guard let picked else { return }
                        chosen = picked
                    }
                case .ai(let difficulty):
                    await pause(0.45)
                    chosen = AIPlayer(difficulty: difficulty).chooseMove(from: moves, in: engine.state, using: &generator)
                case .remote:
                    return
                }
                if Task.isCancelled { return }
                guard await perform(RecordedAction(color: color, action: chosen.action), publish: seat.controller != .remote) else { return }
            }
        }
    }

    /// Nước không cần hỏi người chơi, nếu có: khi đó quân tự đi, không bắt người chơi bấm.
    /// Các quân còn trong chuồng là như nhau nên nếu mọi nước đều là ra quân thì lấy ngẫu nhiên một quân.
    private static func onlyChoice(among moves: [Move]) -> Move? {
        guard let first = moves.first else { return nil }
        if moves.allSatisfy({ $0.kind == .release }) {
            // Hai viên cùng cho phép ra quân (ví dụ đôi 6) vẫn là một lựa chọn: dùng viên đầu.
            return moves.filter { $0.use == first.use }.randomElement()
        }
        guard moves.allSatisfy({ $0.horse == first.horse }) else { return nil }
        if moves.allSatisfy({ $0.to == first.to }) { return first }
        // Một quân, nhiều cách đi: chỉ hỏi người chơi khi có cách đáng cân nhắc (bay, đá quân, lên bậc đích).
        // Còn lại quân tự đi quãng dài nhất mà xúc xắc cho phép (chế độ nhanh: cộng hai viên nếu được).
        if moves.contains(where: { $0.kind == .fly || !$0.captures.isEmpty || $0.to.isHome }) { return nil }
        return moves.max { $0.path.count < $1.path.count }
    }

    private func prompt(for moves: [Move]) -> String {
        let dice = engine.state.remainingDice
        if dice.count == 2 {
            return L("Chọn quân, rồi chọn ô đích (dùng \(dice[0]), \(dice[1]) hoặc cộng \(dice[0] + dice[1]))", "Pick a piece, then a destination (use \(dice[0]), \(dice[1]) or their sum \(dice[0] + dice[1]))")
        }
        if moves.contains(where: { $0.kind == .fly }) {
            return L("Chọn quân: đi 1 bước hoặc bay tới cửa chuồng kế tiếp", "Pick a piece: move 1 step or fly to the next gate square")
        }
        return L("Chọn một quân để đi \(dice.first ?? 0) bước", "Pick a piece to move \(dice.first ?? 0) steps")
    }

    /// Đánh dấu viên nào của lần đổ gần nhất đã dùng, dựa trên các viên còn lại trong trạng thái ván.
    private func refreshDiceUsage() {
        var remaining = engine.state.remainingDice
        diceUsed = engine.state.rolledDice.map { value in
            if let index = remaining.firstIndex(of: value) {
                remaining.remove(at: index)
                return false
            }
            return true
        }
        if diceUsed.count != diceFaces.count { diceUsed = Array(repeating: false, count: diceFaces.count) }
    }

    /// Áp dụng một hành động qua `GameEngine`, ghi vào nhật ký, diễn hoạt, và (nếu là hành động của người chơi ở
    /// máy này trong ván chơi mạng) gửi đi. Trả về `false` nếu hành động bị từ chối hoặc ván bị huỷ.
    private func perform(_ recorded: RecordedAction, publish: Bool) async -> Bool {
        guard let events = try? engine.apply(recorded.action, by: recorded.color) else {
            message = L("Dữ liệu ván không hợp lệ", "Invalid game data")
            return false
        }
        log.append(recorded.action, by: recorded.color)
        if case .roll(let value, let second) = recorded.action {
            diceOwner = recorded.color
            await animateDice(to: [value] + (second.map { [$0] } ?? []))
        }
        await present(events)
        refreshDiceUsage()
        if publish, let sync {
            guard await sync.publish(log: log, state: engine.state) else { return false }
        }
        return !Task.isCancelled
    }

    private func applySettings() {
        scene.durationScale = settings.animationSpeed.durationScale
        scene.effectsEnabled = !settings.reducedEffects
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds * settings.animationSpeed.durationScale))
    }

    private func animateDice(to values: [Int]) async {
        diceRolling = true
        diceUsed = Array(repeating: false, count: values.count)
        audio.play(Bool.random() ? .diceRoll1 : .diceRoll2)
        for _ in 0..<9 {
            // Các mặt nháy trong lúc lăn chỉ để trang trí, không liên quan tới kết quả.
            diceFaces = values.map { _ in Int.random(in: GameRules.diceRange) }
            diceTilt = Double.random(in: -24...24)
            try? await Task.sleep(for: .seconds(0.065 * settings.animationSpeed.durationScale))
        }
        diceFaces = values
        diceTilt = 0
        diceRolling = false
        await pause(0.3)
    }

    private func present(_ events: [GameEvent]) async {
        for event in events {
            if Task.isCancelled { return }
            switch event {
            case .rolled, .turnChanged:
                break
            case .resigned(let player):
                message = L("\(seat(player).name) đã rời ván", "\(seat(player).name) left the game")
                scene.sync(with: engine.state)
                state = engine.state
                await pause(0.9)
            case .moved(let move):
                let name = seat(move.horse.color).name
                if let victim = move.captures.first {
                    message = L("\(name) đá quân của \(seat(victim.color).name)!", "\(name) captured \(seat(victim.color).name)'s piece!")
                } else if let rung = move.to.homeRung {
                    message = L("\(name) lên bậc \(rung)", "\(name) reached rung \(rung)")
                } else if move.kind == .release {
                    message = L("\(name) ra quân", "\(name) released a piece")
                } else if move.kind == .fly {
                    message = L("\(name) bay tới cửa chuồng", "\(name) flew to a gate square")
                }
                await scene.animate(move)
            case .noLegalMove(let player, _):
                message = L("\(seat(player).name) không có nước đi", "\(seat(player).name) has no move")
                if seat(player).controller == .human { audio.play(.uiError) }
                await pause(0.9)
            case .bonusTurn(let player):
                state = engine.state
                message = L("\(seat(player).name) được đổ thêm lượt!", "\(seat(player).name) rolls again!")
                await pause(0.5)
            case .bonusLimitReached(let player):
                message = L("\(seat(player).name) đổ thưởng quá số lần cho phép — mất lượt", "\(seat(player).name) used up the bonus rolls — turn lost")
                await pause(0.9)
            case .gameOver(let winner):
                state = engine.state
                finish(winner: winner, celebrate: true)
                await pause(1.4)
            }
        }
        state = engine.state
        scene.sync(with: engine.state)
    }

    private func finish(winner: PlayerColor, celebrate: Bool) {
        message = seat(winner).controller == .human ? L("Bạn thắng!", "You win!") : L("\(seat(winner).name) thắng!", "\(seat(winner).name) wins!")
        if celebrate {
            audio.play(.win)
            scene.celebrate(winner: winner)
        }
        Task { [weak self] in
            if celebrate { try? await Task.sleep(for: .seconds(1.4)) }
            guard let self, self.result == nil else { return }
            self.result = MatchResult(winner: winner, standings: self.engine.state.standings(),
                                      duration: Date().timeIntervalSince(self.startedAt), turns: self.engine.state.turnNumber)
        }
    }
}
