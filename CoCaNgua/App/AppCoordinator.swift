import SwiftUI
import GameCore
import Observation

enum AppScreen: Equatable {
    case mainMenu
    case singlePlayerSetup
    case onlineLobby
    case settings
    case game
}

/// Điều hướng giữa các màn hình và giữ các đối tượng sống suốt vòng đời ứng dụng.
@MainActor
@Observable
final class AppCoordinator {
    private(set) var screen: AppScreen = .mainMenu
    private(set) var session: GameSession?
    let settings = GameSettings()
    let gameCenter = GameCenterManager()
    let online: OnlineMatchManager
    /// Phòng chơi trực tiếp theo mã.
    let rooms: RoomManager
    private let audio = AudioManager.shared

    init() {
        online = OnlineMatchManager(settings: settings)
        rooms = RoomManager(settings: settings)
        online.onOpenSession = { [weak self] session in self?.present(session) }
        online.onMatchInvalidated = { [weak self] in self?.showOnlineLobby() }
        rooms.onOpenSession = { [weak self] session in self?.present(session) }
        rooms.onRoomClosed = { [weak self] in self?.showOnlineLobby() }
        gameCenter.onSignedIn = { [weak self] in
            guard let self else { return }
            self.online.startListening()
            Task { await self.online.refresh() }
        }
    }

    func bootstrap() {
        audio.soundVolume = settings.soundVolume
        audio.musicVolume = settings.musicVolume
        audio.preload()
        audio.startMusic()
    }

    func applyAudioSettings() {
        audio.soundVolume = settings.soundVolume
        audio.musicVolume = settings.musicVolume
    }

    func click() { audio.play(.uiClick) }

    func showMainMenu() {
        closeSession()
        screen = .mainMenu
    }

    /// Phòng chờ chơi mạng. Đăng nhập Game Center được thử ngay khi vào.
    func showOnlineLobby() {
        closeSession()
        screen = .onlineLobby
        gameCenter.signIn()
        if gameCenter.isSignedIn { Task { await online.refresh() } }
    }

    /// Rời ván chơi mạng đang mở. `resign` = bỏ cuộc; nếu không, trận được giữ lại để vào tiếp sau.
    func leaveOnlineMatch(resign: Bool) {
        if rooms.isActive {
            rooms.leave()
            showOnlineLobby()
            return
        }
        Task {
            await online.leaveActive(resign: resign)
            showOnlineLobby()
        }
    }

    private func closeSession() {
        // Rời màn chơi của một phòng trực tiếp là rời phòng; ở sảnh chờ thì phòng được giữ.
        if rooms.isPlaying { rooms.leave() }
        if online.hasActiveMatch { Task { await online.leaveActive(resign: false) } }
        session?.stop()
        session = nil
        audio.musicDucked = false
    }

    private func present(_ session: GameSession) {
        self.session?.stop()
        self.session = session
        audio.musicDucked = true
        screen = .game
        session.start()
    }

    func showSettings() { screen = .settings }

    func showSinglePlayerSetup() { screen = .singlePlayerSetup }

    /// Bắt đầu ván chơi đơn theo lựa chọn đang lưu trong cài đặt (màu, số đối thủ, độ khó).
    /// `initialState` và `generator` chỉ dùng cho công cụ chụp ảnh gỡ lỗi.
    func startSinglePlayer(initialState: GameState? = nil, generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        closeSession()
        let opponents = initialState.map { $0.players.count - 1 } ?? settings.lastOpponentCount
        let configuration = MatchConfiguration.singlePlayer(humanColor: settings.lastHumanColor, opponents: opponents,
                                                            difficulty: settings.lastDifficulty,
                                                            rules: initialState?.rules ?? settings.rules)
        present(GameSession(configuration: configuration, settings: settings, initialState: initialState, generator: generator))
    }

    #if os(macOS)
    func quit() { NSApp.terminate(nil) }
    #endif
}
