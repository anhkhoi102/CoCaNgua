import Foundation
import GameCore
@preconcurrency import GameKit
import Observation
import OnlineCore

/// Một trận trong danh sách của phòng chờ.
struct OnlineMatchSummary: Identifiable, Equatable {
    let id: String
    var opponents: String
    var status: String
    var isMyTurn: Bool
    var isFinished: Bool
    /// Mã phòng, nếu trận được tạo hoặc vào bằng mã trên máy này.
    var roomCode: String?
}

/// Ghép trận, gửi/nhận lượt và khôi phục trận qua `GKTurnBasedMatch`.
///
/// Game Center chỉ lưu và chuyển `matchData`; nó không biết luật chơi. Mọi dữ liệu nhận về đều đi qua
/// `OnlineMatchValidator` (phát lại bằng `GameEngine`, kiểm tra lịch sử và người giữ lượt) trước khi được dùng.
/// LƯU Ý: lớp này chưa được chạy thử với Game Center thật (cần tài khoản Apple Developer); xem Docs/GAME_CENTER_SETUP.md.
@MainActor
@Observable
final class OnlineMatchManager: NSObject, MatchSyncing {
    private(set) var matches: [OnlineMatchSummary] = []
    private(set) var isBusy = false
    /// Thông báo lỗi để hiển thị ở phòng chờ hoặc trong ván.
    var errorMessage: String?
    /// Gọi khi một trận đã sẵn sàng để hiển thị.
    var onOpenSession: ((GameSession) -> Void)?
    /// Gọi khi trận đang mở không thể tiếp tục (dữ liệu không hợp lệ).
    var onMatchInvalidated: (() -> Void)?

    private struct ActiveMatch {
        var match: GKTurnBasedMatch
        var data: OnlineMatchData
        let localSeat: Int
        let session: GameSession
    }

    private let settings: GameSettings
    private let store = OnlineMatchStore()
    private var active: ActiveMatch?
    private var nudge: CheckedContinuation<Void, Never>?
    private var isListening = false
    private var awaitingMatchmaker = false

    var hasActiveMatch: Bool { active != nil }

    init(settings: GameSettings) {
        self.settings = settings
    }

    /// Bắt đầu nhận sự kiện lượt và lời mời. Gọi sau khi đăng nhập Game Center.
    func startListening() {
        guard !isListening else { return }
        isListening = true
        GKLocalPlayer.local.register(self)
    }

    // MARK: - Danh sách trận và ghép trận

    func refresh() async {
        do {
            let loaded = try await GKTurnBasedMatch.loadMatches()
            matches = loaded.compactMap(summary(of:))
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Ghép trận công khai: Game Center tạo trận ngay và điền các chỗ trống khi có người khác cũng đang tìm trận.
    func findPublicMatch(playerCount: Int) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let match = try await GKTurnBasedMatch.find(for: request(playerCount: playerCount))
            try await open(match)
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Trận riêng: mở giao diện của Game Center để mời bạn bè.
    func invitePlayers(playerCount: Int, recipients: [GKPlayer] = []) {
        let request = request(playerCount: playerCount)
        if !recipients.isEmpty { request.recipients = recipients }
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = self
        controller.showExistingMatches = false
        controller.matchmakingMode = .inviteOnly
        awaitingMatchmaker = true
        GameCenterManager.present(controller)
    }

    private func request(playerCount: Int) -> GKMatchRequest {
        let count = min(max(playerCount, GameRules.minPlayers), GameRules.maxPlayers)
        let request = GKMatchRequest()
        request.minPlayers = count
        request.maxPlayers = count
        request.defaultNumberOfPlayers = count
        request.inviteMessage = L("Chơi Cờ Cá Ngựa với mình nhé!", "Come play Cờ Cá Ngựa with me!")
        return request
    }

    func open(matchID: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await open(try await GKTurnBasedMatch.load(withID: matchID))
        } catch {
            errorMessage = describe(error)
        }
    }

    func remove(matchID: String) async {
        do {
            let match = try await GKTurnBasedMatch.load(withID: matchID)
            try await match.remove()
            store.forget(matchID)
        } catch {
            errorMessage = describe(error)
        }
        await refresh()
    }

    /// Tạo trận mới với cùng những người chơi của trận vừa kết thúc.
    func rematch() async {
        guard let match = active?.match else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await match.rematch()
            closeActive()
            try await open(next)
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Mở và rời trận

    private func open(_ match: GKTurnBasedMatch) async throws {
        closeActive()
        let matchID = match.matchID
        let raw = try await match.loadMatchData()
        let snapshot = try OnlineMatchValidator.load(raw, playerCount: match.participants.count, newMatchRules: settings.rules)
        try validate(snapshot, for: match)
        guard let localSeat = seat(of: GKLocalPlayer.local, in: match) else { throw OnlineMatchError.invalidSeats }
        store.remember(snapshot.log, for: matchID)

        let seats = snapshot.data.seatColors.enumerated().map { index, color in
            Seat(color: color, name: displayName(of: match.participants[index], isLocal: index == localSeat),
                 controller: index == localSeat ? .human : .remote)
        }.sorted { $0.color.rawValue < $1.color.rawValue }
        let session = GameSession(configuration: MatchConfiguration(seats: seats, rules: snapshot.data.rules), settings: settings,
                                  initialState: snapshot.state, log: snapshot.log, sync: self)
        session.roomCode = store.roomCode(for: matchID)
        active = ActiveMatch(match: match, data: snapshot.data, localSeat: localSeat, session: session)
        errorMessage = nil
        onOpenSession?(session)
    }

    /// Rời trận đang mở. `resign` = bỏ cuộc (trận tiếp tục cho người khác); nếu không, trận được giữ để vào lại sau.
    func leaveActive(resign: Bool) async {
        guard let current = active else { return }
        current.session.stop()
        if resign, current.match.status != .ended {
            do {
                try await quit(current)
            } catch {
                errorMessage = describe(error)
            }
        }
        closeActive()
        await refresh()
    }

    private func closeActive() {
        active?.session.stop()
        active = nil
        fireNudge()
    }

    private func quit(_ current: ActiveMatch) async throws {
        let match = current.match
        guard holdsTurn(current) else {
            try await match.participantQuitOutOfTurn(with: .quit)
            return
        }
        var data = current.data
        var log = current.session.log
        log.append(.resign, by: data.seatColors[current.localSeat])
        data.actionLog = log
        let snapshot = try OnlineMatchValidator.snapshot(data)
        let payload = try data.encoded(maximumSize: match.matchDataMaximumSize)
        if snapshot.state.isFinished {
            match.participants[current.localSeat].matchOutcome = .quit
            setOutcomes(in: match, snapshot: snapshot)
            try await match.endMatchInTurn(withMatch: payload)
        } else {
            try await match.participantQuitInTurn(with: .quit, nextParticipants: nextParticipants(in: match, snapshot: snapshot, localSeat: current.localSeat),
                                                 turnTimeout: GKTurnTimeoutDefault, match: payload)
        }
        store.remember(log, for: match.matchID)
    }

    // MARK: - MatchSyncing

    func publish(log: ActionLog, state: GameState) async -> Bool {
        var attempt = 0
        while let current = active {
            // Chỉ người đang giữ lượt theo Game Center mới được ghi dữ liệu trận.
            guard holdsTurn(current), current.match.status != .ended else { return true }
            var data = current.data
            data.actionLog = log
            do {
                let snapshot = try OnlineMatchValidator.snapshot(data)
                let payload = try data.encoded(maximumSize: current.match.matchDataMaximumSize)
                let outOfPlay = outOfPlaySeats(in: current.match)
                if state.isFinished {
                    setOutcomes(in: current.match, snapshot: snapshot)
                    try await current.match.endMatchInTurn(withMatch: payload)
                } else if let next = snapshot.seatToMove, next != current.localSeat, !outOfPlay.contains(next) {
                    try await current.match.endTurn(withNextParticipants: nextParticipants(in: current.match, snapshot: snapshot, localSeat: current.localSeat),
                                                    turnTimeout: GKTurnTimeoutDefault, match: payload)
                } else {
                    // Vẫn là lượt của máy này (đổ thêm, chưa đi quân), hoặc người kế tiếp đã rời trận và sẽ được xử bỏ cuộc.
                    try await current.match.saveCurrentTurn(withMatch: payload)
                }
                active?.data = data
                store.remember(log, for: current.match.matchID)
                current.session.connectionNote = nil
                return true
            } catch let error as OnlineMatchError {
                errorMessage = describe(error)
                return false
            } catch {
                attempt += 1
                current.session.connectionNote = L("Mất kết nối — đang thử lại…", "Connection lost — retrying…")
                try? await Task.sleep(for: .seconds(min(pow(2, Double(attempt)), 15)))
            }
        }
        return false
    }

    func remoteActions(after count: Int) async -> [RecordedAction]? {
        while let current = active {
            do {
                if let actions = try await checkForUpdates(current, after: count) { return actions }
                active?.session.connectionNote = nil
            } catch let error as OnlineMatchError {
                errorMessage = describe(error)
                onMatchInvalidated?()
                return nil
            } catch {
                active?.session.connectionNote = L("Mất kết nối — đang thử lại…", "Connection lost — retrying…")
            }
            // Chờ sự kiện lượt từ Game Center; hỏi lại định kỳ phòng khi sự kiện bị lỡ.
            await waitForNudge(seconds: 20)
        }
        return nil
    }

    func pendingActions(after count: Int) -> [RecordedAction] {
        guard let current = active, holdsTurn(current) else { return [] }
        var data = current.data
        data.actionLog = current.session.log
        guard let snapshot = try? OnlineMatchValidator.snapshot(data) else { return [] }
        return OnlineMatchValidator.reconciliation(outOfPlaySeats: outOfPlaySeats(in: current.match), in: snapshot)
    }

    private func checkForUpdates(_ current: ActiveMatch, after count: Int) async throws -> [RecordedAction]? {
        let match = try await GKTurnBasedMatch.load(withID: current.match.matchID)
        let raw = try await match.loadMatchData()
        guard active?.match.matchID == match.matchID else { return nil }
        active?.match = match
        let snapshot = try OnlineMatchValidator.load(raw, playerCount: match.participants.count, newMatchRules: current.data.rules)
        // Bản đọc về có thể cũ hơn những gì máy này đã biết (dịch vụ chưa kịp cập nhật): bỏ qua, không coi là gian lận.
        let known = store.knownLog(for: match.matchID)
        if let known, snapshot.log.count < known.count, snapshot.log.isPrefix(of: known) { return nil }
        try validate(snapshot, for: match)
        for (index, color) in snapshot.data.seatColors.enumerated() where index != current.localSeat {
            current.session.rename(color, to: displayName(of: match.participants[index], isLocal: false))
        }
        if snapshot.log.count > count {
            active?.data = snapshot.data
            store.remember(snapshot.log, for: match.matchID)
            return Array(snapshot.actions.dropFirst(count))
        }
        if let refreshed = active, holdsTurn(refreshed) {
            let fixes = OnlineMatchValidator.reconciliation(outOfPlaySeats: outOfPlaySeats(in: match), in: snapshot)
            if !fixes.isEmpty { return fixes }
        }
        return nil
    }

    private func validate(_ snapshot: OnlineMatchSnapshot, for match: GKTurnBasedMatch) throws {
        let currentSeat = match.status == .ended ? nil : match.currentParticipant.flatMap { seat(of: $0, in: match) }
        try OnlineMatchValidator.validate(snapshot, known: store.knownLog(for: match.matchID), currentSeat: currentSeat,
                                          outOfPlaySeats: outOfPlaySeats(in: match))
    }

    private func waitForNudge(seconds: Double) async {
        await withCheckedContinuation { continuation in
            nudge = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.fireNudge()
            }
        }
    }

    private func fireNudge() {
        nudge?.resume()
        nudge = nil
    }

    // MARK: - Ánh xạ người tham gia

    private func seat(of player: GKPlayer, in match: GKTurnBasedMatch) -> Int? {
        match.participants.firstIndex { $0.player?.gamePlayerID == player.gamePlayerID }
    }

    private func seat(of participant: GKTurnBasedParticipant, in match: GKTurnBasedMatch) -> Int? {
        if let player = participant.player, let index = seat(of: player, in: match) { return index }
        return match.participants.firstIndex { $0 === participant }
    }

    private func holdsTurn(_ current: ActiveMatch) -> Bool {
        guard let participant = current.match.currentParticipant else { return false }
        return seat(of: participant, in: current.match) == current.localSeat
    }

    /// Những chỗ ngồi Game Center báo đã rời trận (thoát, hết hạn lượt...).
    private func outOfPlaySeats(in match: GKTurnBasedMatch) -> Set<Int> {
        guard match.status != .ended else { return [] }
        return Set(match.participants.indices.filter { match.participants[$0].matchOutcome != .none || match.participants[$0].status == .done })
    }

    /// Thứ tự nhận lượt: người tới lượt trong ván trước, rồi lần lượt những người còn chơi, máy này sau cùng.
    private func nextParticipants(in match: GKTurnBasedMatch, snapshot: OnlineMatchSnapshot, localSeat: Int) -> [GKTurnBasedParticipant] {
        let count = match.participants.count
        let start = snapshot.seatToMove ?? (localSeat + 1) % count
        let outOfPlay = outOfPlaySeats(in: match)
        var order = (0..<count).map { (start + $0) % count }.filter { $0 != localSeat && !outOfPlay.contains($0) }
        order.append(localSeat)
        return order.map { match.participants[$0] }
    }

    private func setOutcomes(in match: GKTurnBasedMatch, snapshot: OnlineMatchSnapshot) {
        let winnerSeat = snapshot.state.winner.flatMap(snapshot.seat(of:))
        for (index, participant) in match.participants.enumerated() where participant.matchOutcome == .none {
            participant.matchOutcome = index == winnerSeat ? .won : .lost
        }
    }

    private func displayName(of participant: GKTurnBasedParticipant, isLocal: Bool) -> String {
        if isLocal { return L("Bạn", "You") }
        return participant.player?.displayName ?? L("Đang chờ người chơi", "Waiting for a player")
    }

    private func summary(of match: GKTurnBasedMatch) -> OnlineMatchSummary? {
        guard let localSeat = seat(of: GKLocalPlayer.local, in: match) else { return nil }
        let others = match.participants.enumerated().filter { $0.offset != localSeat }
            .map { displayName(of: $0.element, isLocal: false) }.joined(separator: ", ")
        let finished = match.status == .ended
        let myTurn = !finished && match.currentParticipant.flatMap { seat(of: $0, in: match) } == localSeat
        let status: String
        if finished {
            status = switch match.participants[localSeat].matchOutcome {
            case .won: L("Đã kết thúc — bạn thắng", "Finished — you won")
            case .quit: L("Đã kết thúc — bạn bỏ cuộc", "Finished — you resigned")
            default: L("Đã kết thúc", "Finished")
            }
        } else if myTurn {
            status = L("Tới lượt bạn", "Your turn")
        } else if let current = match.currentParticipant {
            status = L("Đang chờ \(displayName(of: current, isLocal: false))", "Waiting for \(displayName(of: current, isLocal: false))")
        } else {
            status = L("Đang ghép trận", "Matchmaking")
        }
        return OnlineMatchSummary(id: match.matchID, opponents: others, status: status, isMyTurn: myTurn, isFinished: finished,
                                  roomCode: store.roomCode(for: match.matchID))
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? OnlineMatchError {
            switch error {
            case .newerFormat: return L("Trận này được tạo bằng phiên bản mới hơn. Hãy cập nhật Cờ Cá Ngựa để chơi tiếp.", "This match was created with a newer version. Update Cờ Cá Ngựa to keep playing.")
            case .historyRewritten, .illegalAction, .turnMismatch:
                return L("Dữ liệu trận không hợp lệ (có nước đi sai luật hoặc lịch sử bị sửa). Không thể tiếp tục trận này.", "The match data is invalid (an illegal move or an altered history). This match cannot continue.")
            case .tooLarge: return L("Trận quá dài, không lưu thêm được.", "This match is too long to save any further.")
            case .corrupt, .invalidSeats, .invalidRules: return L("Không đọc được dữ liệu trận.", "The match data could not be read.")
            }
        }
        return error.localizedDescription
    }

    // MARK: - Sự kiện từ Game Center (chạy trên luồng chính)

    fileprivate func handleTurnEvent(matchID: String, didBecomeActive: Bool) async {
        if active?.match.matchID == matchID {
            fireNudge()
        } else if awaitingMatchmaker || (didBecomeActive && active == nil) {
            // Trận vừa tạo từ giao diện mời, hoặc người chơi bấm vào thông báo lượt.
            awaitingMatchmaker = false
            GameCenterManager.dismissDialog()
            await open(matchID: matchID)
        }
        await refresh()
    }

    fileprivate func handleMatchEnded(matchID: String) async {
        if active?.match.matchID == matchID { fireNudge() }
        await refresh()
    }

    fileprivate func handleMatchmakerClosed(errorMessage: String?) {
        awaitingMatchmaker = false
        GameCenterManager.dismissDialog()
        if let errorMessage { self.errorMessage = errorMessage }
    }

    fileprivate func handleQuitRequest(matchID: String) async {
        if active?.match.matchID == matchID {
            await leaveActive(resign: true)
        } else if let match = try? await GKTurnBasedMatch.load(withID: matchID) {
            try? await match.participantQuitOutOfTurn(with: .quit)
            await refresh()
        }
    }
}

// MARK: - GKLocalPlayerListener

extension OnlineMatchManager: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        let matchID = match.matchID
        Task { @MainActor in await self.handleTurnEvent(matchID: matchID, didBecomeActive: didBecomeActive) }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        let matchID = match.matchID
        Task { @MainActor in await self.handleMatchEnded(matchID: matchID) }
    }

    nonisolated func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        let matchID = match.matchID
        Task { @MainActor in await self.handleQuitRequest(matchID: matchID) }
    }

    nonisolated func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        nonisolated(unsafe) let recipients = playersToInvite
        Task { @MainActor in self.invitePlayers(playerCount: min(max(recipients.count + 1, 2), 4), recipients: recipients) }
    }
}

// MARK: - GKTurnBasedMatchmakerViewControllerDelegate

extension OnlineMatchManager: GKTurnBasedMatchmakerViewControllerDelegate {
    nonisolated func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        Task { @MainActor in self.handleMatchmakerClosed(errorMessage: nil) }
    }

    nonisolated func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.handleMatchmakerClosed(errorMessage: message) }
    }
}
