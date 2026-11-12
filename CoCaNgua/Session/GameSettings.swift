import Foundation
import GameCore
import Observation

enum AnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case slow, normal, fast
    var id: String { rawValue }

    /// Hệ số nhân thời lượng hoạt ảnh.
    var durationScale: Double {
        switch self {
        case .slow: 1.5
        case .normal: 1.0
        case .fast: 0.5
        }
    }

    var title: String {
        switch self {
        case .slow: L("Chậm", "Slow")
        case .normal: L("Vừa", "Medium")
        case .fast: L("Nhanh", "Fast")
        }
    }
}

enum RulesPreset: String, CaseIterable, Identifiable {
    case traditional, modern, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .traditional: L("Truyền thống", "Traditional")
        case .modern: L("Hiện đại", "Modern")
        case .custom: L("Tuỳ chỉnh", "Custom")
        }
    }
}

/// Cài đặt của người chơi, lưu trong UserDefaults.
@MainActor
@Observable
final class GameSettings {
    var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) } }
    var musicVolume: Double { didSet { defaults.set(musicVolume, forKey: Keys.musicVolume) } }
    var animationSpeed: AnimationSpeed { didSet { defaults.set(animationSpeed.rawValue, forKey: Keys.animationSpeed) } }
    /// Tắt hiệu ứng hạt (lấp lánh, pháo giấy).
    var reducedEffects: Bool { didSet { defaults.set(reducedEffects, forKey: Keys.reducedEffects) } }
    /// Tự đi khi chỉ có đúng một nước hợp lệ.
    var autoMoveSingleOption: Bool { didSet { defaults.set(autoMoveSingleOption, forKey: Keys.autoMove) } }
    /// Kiểu quân cờ; áp dụng từ ván mới.
    var pieceStyle: PieceStyle { didSet { defaults.set(pieceStyle.rawValue, forKey: Keys.pieceStyle) } }
    /// Ngôn ngữ trong game (thanh menu macOS luôn là tiếng Anh).
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            Localization.language = language
        }
    }
    var startInFullScreen: Bool { didSet { defaults.set(startInFullScreen, forKey: Keys.fullScreen) } }
    /// Lựa chọn gần nhất ở màn thiết lập chơi đơn.
    var lastHumanColor: PlayerColor { didSet { defaults.set(lastHumanColor.rawValue, forKey: Keys.humanColor) } }
    var lastOpponentCount: Int { didSet { defaults.set(lastOpponentCount, forKey: Keys.opponents) } }
    var lastDifficulty: AIDifficulty { didSet { defaults.set(lastDifficulty.rawValue, forKey: Keys.difficulty) } }
    /// Luật áp dụng cho ván mới.
    var rules: RulesConfiguration {
        didSet { if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Keys.rules) } }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.8
        musicVolume = defaults.object(forKey: Keys.musicVolume) as? Double ?? 0.4
        animationSpeed = defaults.string(forKey: Keys.animationSpeed).flatMap(AnimationSpeed.init) ?? .normal
        reducedEffects = defaults.bool(forKey: Keys.reducedEffects)
        autoMoveSingleOption = defaults.object(forKey: Keys.autoMove) as? Bool ?? true
        pieceStyle = defaults.string(forKey: Keys.pieceStyle).flatMap(PieceStyle.init) ?? .knight
        startInFullScreen = defaults.bool(forKey: Keys.fullScreen)
        let savedLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .vi
        language = savedLanguage
        Localization.language = savedLanguage
        lastHumanColor = (defaults.object(forKey: Keys.humanColor) as? Int).flatMap(PlayerColor.init) ?? .red
        lastOpponentCount = min(max(defaults.object(forKey: Keys.opponents) as? Int ?? 3, 1), 3)
        lastDifficulty = defaults.string(forKey: Keys.difficulty).flatMap(AIDifficulty.init) ?? .normal
        let saved = defaults.data(forKey: Keys.rules).flatMap { try? JSONDecoder().decode(RulesConfiguration.self, from: $0) }
        rules = saved.flatMap { $0.isValid() ? $0 : nil } ?? .traditional
        // Cản đường giờ là luật cố định (không còn công tắc); bỏ giá trị cũ đã lưu nếu có.
        rules.blocking = true
    }

    var rulesPreset: RulesPreset {
        get { rules == .traditional ? .traditional : (rules == .modern ? .modern : .custom) }
        set {
            switch newValue {
            case .traditional: rules = .traditional
            case .modern: rules = .modern
            case .custom: break
            }
        }
    }

    private enum Keys {
        static let soundVolume = "soundVolume"
        static let musicVolume = "musicVolume"
        static let animationSpeed = "animationSpeed"
        static let reducedEffects = "reducedEffects"
        static let autoMove = "autoMoveSingleOption"
        static let pieceStyle = "pieceStyle"
        static let language = "language"
        static let fullScreen = "startInFullScreen"
        static let humanColor = "lastHumanColor"
        static let opponents = "lastOpponentCount"
        static let difficulty = "lastDifficulty"
        static let rules = "rules"
    }
}
