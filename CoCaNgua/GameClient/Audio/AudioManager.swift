import AVFoundation

enum SoundEffect: String, CaseIterable {
    case diceShake = "dice_shake"
    case diceRoll1 = "dice_roll_1"
    case diceRoll2 = "dice_roll_2"
    case step = "step_1"
    case land
    case release
    case capture
    case climb
    case win
    case yourTurn = "your_turn"
    case uiClick = "ui_click"
    case uiSelect = "ui_select"
    case uiError = "ui_error"
}

/// Phát hiệu ứng âm thanh và nhạc nền. Âm lượng lấy từ cài đặt.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    var soundVolume: Double = 0.8 { didSet { players.values.joined().forEach { $0.volume = Float(soundVolume) } } }
    var musicVolume: Double = 0.4 { didSet { applyMusicVolume() } }
    /// Trong ván nhạc nhỏ hơn để nghe rõ hiệu ứng.
    var musicDucked = false { didSet { applyMusicVolume() } }

    private var players: [SoundEffect: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?

    private init() {}

    /// Nạp sẵn mọi hiệu ứng để lần phát đầu không bị trễ.
    func preload() {
        #if os(iOS)
        // Tôn trọng nút gạt im lặng và không ngắt nhạc người chơi đang nghe.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for effect in SoundEffect.allCases where players[effect] == nil {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "m4a") else {
                assertionFailure("Thiếu file âm thanh \(effect.rawValue).m4a")
                continue
            }
            // Vài bản sao để cùng một hiệu ứng có thể chồng lên nhau (ví dụ tiếng bước quân).
            players[effect] = (0..<3).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
    }

    func play(_ effect: SoundEffect) {
        guard soundVolume > 0.001, let pool = players[effect], !pool.isEmpty else { return }
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.volume = Float(soundVolume)
        player.currentTime = 0
        player.play()
    }

    func startMusic() {
        if music == nil, let url = Bundle.main.url(forResource: "menu_theme", withExtension: "mp3") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
        }
        applyMusicVolume()
    }

    private func applyMusicVolume() {
        guard let music else { return }
        let volume = musicVolume * (musicDucked ? 0.45 : 1)
        music.setVolume(Float(volume), fadeDuration: 0.4)
        if volume > 0.001 {
            if !music.isPlaying { music.play() }
        } else {
            music.pause()
        }
    }
}
