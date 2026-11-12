import Foundation
import GameCore
@preconcurrency import GameKit
import Observation
import OnlineCore

/// Đường truyền giữa các máy trong một phòng. Bản thật bọc `GKMatch`; bản Debug có đường truyền giả lập trong máy
/// để chạy thử giao thức khi chưa có Game Center.
@MainActor
protocol RoomTransport: AnyObject {
    var localID: String { get }
    var localName: String { get }
    /// Những máy khác đang nối (định danh và tên hiển thị).
    var peers: [(id: String, name: String)] { get }
    var onReceive: ((Data, String) -> Void)? { get set }
    /// Một máy vừa nối (`true`) hoặc vừa rời (`false`).
    var onPeerChange: ((String, Bool) -> Void)? { get set }
    var onFailure: ((String?) -> Void)? { get set }
    func send(_ data: Data) throws
    /// Thôi nhận thêm người (ván bắt đầu).
    func lock()
    func disconnect()
}

/// Đường truyền thật qua trận thời gian thực của Game Center.
@MainActor
final class GameKitRoomTransport: NSObject, RoomTransport, GKMatchDelegate {
    let match: GKMatch
    let localID = GKLocalPlayer.local.gamePlayerID
    let localName = GKLocalPlayer.local.displayName
    var onReceive: ((Data, String) -> Void)?
    var onPeerChange: ((String, Bool) -> Void)?
    var onFailure: ((String?) -> Void)?

    init(match: GKMatch) {
        self.match = match
        super.init()
        match.delegate = self
    }

    var peers: [(id: String, name: String)] { match.players.map { ($0.gamePlayerID, $0.displayName) } }

    func send(_ data: Data) throws { try match.sendData(toAllPlayers: data, with: .reliable) }

    func lock() { GKMatchmaker.shared().finishMatchmaking(for: match) }

    func disconnect() {
        match.delegate = nil
        match.disconnect()
    }

    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let sender = player.gamePlayerID
        Task { @MainActor in self.onReceive?(data, sender) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let playerID = player.gamePlayerID
        let connected = state == .connected
        guard connected || state == .disconnected else { return }
        Task { @MainActor in self.onPeerChange?(playerID, connected) }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in self.onFailure?(message) }
    }
}

/// Phòng chơi trực tiếp theo mã, dùng trận thời gian thực (`GKMatch`) của Game Center. Không có máy chủ riêng.
///
/// - Mã phòng là `playerGroup` của yêu cầu ghép trận: Game Center chỉ nối những máy gửi cùng mã với nhau.
/// - Chủ phòng thấy ai đã vào và bấm Bắt đầu lúc nào tuỳ ý; chỗ còn trống do bot chơi. Bot chạy trên máy chủ phòng.
/// - Mỗi máy tự đổ xúc xắc và đi quân của mình rồi gửi hành động (mã hoá như `ActionLog`) cho các máy khác.
///   Máy nhận phát lại bằng `GameEngine` và kiểm tra người gửi có quyền đi màu đó, nên nước sai luật bị từ chối.
/// - Ai rời phòng giữa ván thì bot của chủ phòng chơi thay. Chủ phòng rời thì ván kết thúc với mọi người.
///
/// LƯU Ý: lớp này chưa được chạy thử với Game Center thật (cần tài khoản Apple Developer và hai tài khoản Game Center).
@MainActor
@Observable
final class RoomManager: MatchSyncing {
    enum Phase: Equatable {
        case idle
        /// Đã gửi mã lên Game Center, chưa có ai khác cùng mã.
        case searching
        /// Đã nối với ít nhất một người; chờ chủ phòng bắt đầu.
        case lobby
        case playing
    }

    struct Member: Identifiable, Equatable {
        let id: String
        var name: String
        var isLocal: Bool
        var isHost: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var roomCode: String?
    private(set) var seatCount = GameRules.maxPlayers
    /// Máy này tạo phòng (và sẽ là người bấm Bắt đầu).
    private(set) var isHost = false
    /// Những người đang ở trong phòng, kể cả máy này.
    private(set) var members: [Member] = []
    var errorMessage: String?
    var onOpenSession: ((GameSession) -> Void)?
    /// Gọi khi ván đang chơi không thể tiếp tục (chủ phòng rời, mất kết nối).
    var onRoomClosed: (() -> Void)?

    private let settings: GameSettings
    private var transport: RoomTransport?
    private var localID = ""
    private var hostID: String?
    private var plan: RoomPlan?
    private var session: GameSession?
    /// Nhật ký đầy đủ mà máy này đã biết (của mình gửi đi và nhận về).
    private var knownLog = ActionLog()
    private var sentCount = 0
    private var departed = Set<String>()
    private var nudge: CheckedContinuation<Void, Never>?
    /// Tăng mỗi lần vào/rời phòng, để bỏ qua kết quả ghép trận của lần trước.
    private var generation = 0

    var isActive: Bool { phase != .idle }
    var isPlaying: Bool { phase == .playing }
    /// Chủ phòng bắt đầu được khi đã có ít nhất một người khác trong phòng.
    var canStart: Bool { isHost && phase == .lobby && members.count >= 2 }

    init(settings: GameSettings) {
        self.settings = settings
    }

    #if DEBUG
    /// Vào thẳng sảnh chờ trên một đường truyền có sẵn (chạy thử giao thức không cần Game Center).
    func debugAttach(_ transport: RoomTransport, code: RoomCode, asHost: Bool) {
        leave()
        generation += 1
        roomCode = code.text
        seatCount = code.playerCount
        isHost = asHost
        attach(transport)
    }
    #endif

    private func attach(_ transport: RoomTransport) {
        self.transport = transport
        localID = transport.localID
        if isHost { hostID = localID }
        transport.onReceive = { [weak self] data, sender in self?.receive(data, from: sender) }
        transport.onPeerChange = { [weak self] playerID, connected in self?.playerChanged(playerID, connected: connected) }
        transport.onFailure = { [weak self] message in
            self?.errorMessage = message ?? L("Mất kết nối với phòng.", "Lost the connection to the room.")
            self?.closeRoom()
        }
        phase = .lobby
        refreshMembers()
        send(.hello(isHost: isHost))
    }

    // MARK: - Tạo và vào phòng

    func createRoom(seatCount: Int) {
        var generator = SystemRandomNumberGenerator()
        enter(RoomCode.generate(playerCount: seatCount, using: &generator), asHost: true)
    }

    /// Vào phòng bằng mã. Trả về `false` nếu mã không hợp lệ.
    @discardableResult
    func joinRoom(code text: String) -> Bool {
        guard let code = RoomCode(text) else {
            errorMessage = L("Mã phòng gồm 6 chữ số. Hãy kiểm tra lại.", "A room code has 6 digits. Please check it.")
            return false
        }
        enter(code, asHost: false)
        return true
    }

    private func enter(_ code: RoomCode, asHost: Bool) {
        leave()
        generation += 1
        let current = generation
        errorMessage = nil
        roomCode = code.text
        seatCount = code.playerCount
        isHost = asHost
        hostID = nil
        localID = GKLocalPlayer.local.gamePlayerID
        phase = .searching
        refreshMembers()
        let request = request(for: code)
        Task {
            do {
                let found = try await GKMatchmaker.shared().findMatch(for: request)
                guard current == generation, phase == .searching else {
                    found.disconnect()
                    return
                }
                attach(GameKitRoomTransport(match: found))
                // Chủ phòng tiếp tục nhận thêm người cho tới khi đủ chỗ hoặc bấm Bắt đầu.
                if isHost, found.players.count + 1 < seatCount {
                    try? await GKMatchmaker.shared().addPlayers(to: found, matchRequest: request)
                    if current == generation { refreshMembers() }
                }
            } catch {
                guard current == generation, phase == .searching else { return }
                errorMessage = error.localizedDescription
                reset()
            }
        }
    }

    private func request(for code: RoomCode) -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = GameRules.minPlayers
        request.maxPlayers = code.playerCount
        request.playerGroup = code.group
        return request
    }

    /// Rời phòng (hoặc huỷ tìm phòng). An toàn khi gọi nhiều lần.
    func leave() {
        guard phase != .idle else { return }
        if phase == .searching { GKMatchmaker.shared().cancel() }
        session?.stop()
        transport?.disconnect()
        reset()
    }

    private func reset() {
        generation += 1
        transport = nil
        plan = nil
        session = nil
        hostID = nil
        isHost = false
        roomCode = nil
        members = []
        knownLog = ActionLog()
        sentCount = 0
        departed = []
        phase = .idle
        fireNudge()
    }

    // MARK: - Sảnh chờ

    private func refreshMembers() {
        var list = [Member(id: localID, name: L("Bạn", "You"), isLocal: true, isHost: isHost)]
        for peer in transport?.peers ?? [] where !departed.contains(peer.id) {
            list.append(Member(id: peer.id, name: peer.name, isLocal: false, isHost: peer.id == hostID))
        }
        members = list
    }

    /// Chủ phòng bắt đầu ván với những người đang có mặt; chỗ trống do bot chơi.
    func start() {
        guard canStart, let transport else { return }
        transport.lock()
        let guests = transport.peers.filter { !departed.contains($0.id) }.map { RoomPlan.Member(playerID: $0.id, name: $0.name) }
        let plan = RoomPlan.make(host: RoomPlan.Member(playerID: localID, name: transport.localName), guests: guests,
                                 seatCount: seatCount, rules: settings.rules) { L("Máy \($0)", "Bot \($0)") }
        send(.start(plan))
        begin(plan)
    }

    private func begin(_ plan: RoomPlan) {
        guard plan.isValid, plan.seat(of: localID) != nil else {
            errorMessage = L("Không vào được ván của phòng này.", "Could not join this room's game.")
            leave()
            return
        }
        self.plan = plan
        hostID = plan.hostID
        knownLog = ActionLog()
        sentCount = 0
        let seats = plan.seats.map { seat -> Seat in
            let controller: SeatController
            if seat.playerID == localID {
                controller = .human
            } else if isHost, seat.isBot {
                controller = .ai(settings.lastDifficulty)
            } else {
                controller = .remote
            }
            return Seat(color: seat.color, name: seat.playerID == localID ? L("Bạn", "You") : seat.name, controller: controller)
        }
        let session = GameSession(configuration: MatchConfiguration(seats: seats, rules: plan.rules), settings: settings, sync: self)
        session.roomCode = roomCode
        session.isLive = true
        self.session = session
        phase = .playing
        onOpenSession?(session)
    }

    // MARK: - Gửi và nhận

    private func send(_ message: RoomMessage) {
        guard let transport, let data = try? message.encoded() else { return }
        do {
            try transport.send(data)
        } catch {
            session?.connectionNote = L("Mất kết nối — đang thử lại…", "Connection lost — retrying…")
        }
    }

    private func receive(_ data: Data, from sender: String) {
        guard let message = RoomMessage.decode(data) else { return }
        switch message {
        case .hello(let senderIsHost):
            if senderIsHost, !isHost { hostID = sender }
            refreshMembers()
            // Người mới vào sau có thể chưa biết ai là chủ phòng.
            if isHost, phase == .lobby { send(.hello(isHost: true)) }
        case .start(let plan):
            // Chỉ nhận lệnh bắt đầu từ chính người được ghi là chủ phòng, và chỉ khi đang ở sảnh.
            guard phase == .lobby, !isHost, plan.hostID == sender else { return }
            begin(plan)
        case .actions(let from, let bytes):
            accept(Array(bytes), from: from, sender: sender)
        }
    }

    /// Nối các hành động nhận được vào nhật ký nếu chúng hợp luật và người gửi có quyền đi các màu đó.
    private func accept(_ bytes: [UInt8], from: Int, sender: String) {
        guard phase == .playing, let plan, from <= knownLog.count else { return }
        // Bỏ phần đã biết (tin nhắn gửi lại).
        let fresh = Array(bytes.dropFirst(knownLog.count - from))
        guard !fresh.isEmpty else { return }
        let candidate = ActionLog(bytes: knownLog.bytes + fresh)
        guard let replayed = try? candidate.replay(colors: plan.colors, rules: plan.rules),
              replayed.actions.dropFirst(knownLog.count).allSatisfy({ mayAct(sender, for: $0.color, in: plan) }) else {
            errorMessage = L("Nhận được nước đi không hợp lệ từ một người chơi. Ván đã dừng.", "Received an invalid move from a player. The game was stopped.")
            closeRoom()
            return
        }
        knownLog = candidate
        fireNudge()
    }

    /// Mỗi người chỉ đi quân của mình. Chủ phòng được đi thêm cho bot và cho người đã rời phòng; vì tin báo "đã rời"
    /// có thể tới máy này muộn hơn nước đi của bot chơi thay, chủ phòng được tin cho mọi màu trừ màu của chính máy này.
    private func mayAct(_ sender: String, for color: PlayerColor, in plan: RoomPlan) -> Bool {
        if plan.mayAct(sender: sender, for: color, departed: departed) { return true }
        return sender == plan.hostID && plan.seat(of: localID)?.color != color
    }

    private func playerChanged(_ playerID: String, connected: Bool) {
        if connected {
            departed.remove(playerID)
            refreshMembers()
            send(.hello(isHost: isHost))
            return
        }
        departed.insert(playerID)
        refreshMembers()
        switch phase {
        case .playing:
            if playerID == hostID {
                errorMessage = L("Chủ phòng đã rời phòng nên ván kết thúc.", "The host left, so the game has ended.")
                closeRoom()
            } else if isHost, let seat = plan?.seat(of: playerID), let session {
                // Bot của chủ phòng chơi thay người vừa rời.
                session.setController(.ai(settings.lastDifficulty), for: seat.color)
                fireNudge()
            }
        case .lobby:
            if playerID == hostID {
                errorMessage = L("Chủ phòng đã rời phòng.", "The host left the room.")
                leave()
            }
        case .idle, .searching:
            break
        }
    }

    private func closeRoom() {
        let wasPlaying = phase == .playing
        leave()
        if wasPlaying { onRoomClosed?() }
    }

    // MARK: - MatchSyncing

    func publish(log: ActionLog, state: GameState) async -> Bool {
        guard phase == .playing else { return false }
        if log.count > sentCount {
            send(.actions(from: sentCount, bytes: Data(log.bytes.dropFirst(sentCount))))
        }
        knownLog = log
        sentCount = log.count
        return true
    }

    func remoteActions(after count: Int) async -> [RecordedAction]? {
        while phase == .playing, let plan, let session {
            if knownLog.count > count, let replayed = try? knownLog.replay(colors: plan.colors, rules: plan.rules) {
                sentCount = knownLog.count
                return Array(replayed.actions.dropFirst(count))
            }
            // Người đang tới lượt vừa rời phòng và bot của máy này chơi thay: trả lượt về cho vòng lặp ván.
            if session.seat(session.state.currentColor).controller != .remote { return [] }
            await withCheckedContinuation { nudge = $0 }
        }
        return nil
    }

    func pendingActions(after count: Int) -> [RecordedAction] { [] }

    private func fireNudge() {
        nudge?.resume()
        nudge = nil
    }
}

#if DEBUG
/// Đường truyền giả lập trong cùng một tiến trình, để chạy thử giao thức phòng khi chưa có Game Center.
@MainActor
final class LoopbackRoomTransport: RoomTransport {
    let localID: String
    let localName: String
    var others: [LoopbackRoomTransport] = []
    private(set) var isConnected = true
    var onReceive: ((Data, String) -> Void)?
    var onPeerChange: ((String, Bool) -> Void)?
    var onFailure: ((String?) -> Void)?

    init(id: String, name: String) {
        localID = id
        localName = name
    }

    var peers: [(id: String, name: String)] { others.filter(\.isConnected).map { ($0.localID, $0.localName) } }

    func send(_ data: Data) throws {
        guard isConnected else { return }
        let sender = localID
        // Giao tin không đồng bộ nhưng giữ đúng thứ tự, như kênh `reliable` của Game Center.
        for other in others where other.isConnected {
            DispatchQueue.main.async { if other.isConnected { other.onReceive?(data, sender) } }
        }
    }

    func lock() {}

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        let leaver = localID
        for other in others { DispatchQueue.main.async { other.onPeerChange?(leaver, false) } }
    }
}
#endif
