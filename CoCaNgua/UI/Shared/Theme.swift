import GameCore
import SwiftUI

/// Bảng màu, phông chữ và tên hiển thị dùng chung cho SwiftUI lẫn SpriteKit.
enum Theme {
    static let fontFamily = "Baloo 2"

    static let board = PlatformColor(srgbRed: 0.99, green: 0.96, blue: 0.88, alpha: 1)
    static let boardEdge = PlatformColor(srgbRed: 0.80, green: 0.66, blue: 0.45, alpha: 1)
    static let cell = PlatformColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let cellStroke = PlatformColor(srgbRed: 0.78, green: 0.72, blue: 0.62, alpha: 1)
    static let tableTop = PlatformColor(srgbRed: 0.10, green: 0.36, blue: 0.33, alpha: 1)
    static let tableBottom = PlatformColor(srgbRed: 0.05, green: 0.21, blue: 0.22, alpha: 1)
    static let ink = PlatformColor(srgbRed: 0.17, green: 0.15, blue: 0.20, alpha: 1)

    static func color(_ player: PlayerColor) -> PlatformColor {
        switch player {
        case .red: PlatformColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)
        case .blue: PlatformColor(srgbRed: 0.22, green: 0.50, blue: 0.96, alpha: 1)
        case .green: PlatformColor(srgbRed: 0.18, green: 0.68, blue: 0.42, alpha: 1)
        case .yellow: PlatformColor(srgbRed: 0.96, green: 0.70, blue: 0.08, alpha: 1)
        }
    }

    static func darkColor(_ player: PlayerColor) -> PlatformColor {
        color(player).blended(withFraction: 0.35, of: .black) ?? color(player)
    }

    static func lightColor(_ player: PlayerColor) -> PlatformColor {
        color(player).blended(withFraction: 0.72, of: .white) ?? color(player)
    }

    static func name(_ player: PlayerColor) -> String {
        switch player {
        case .red: L("Đỏ", "Red")
        case .blue: L("Xanh dương", "Blue")
        case .green: L("Xanh lá", "Green")
        case .yellow: L("Vàng", "Yellow")
        }
    }

    /// Phông Baloo 2 cho SpriteKit; lùi về phông hệ thống bo tròn nếu phông chưa được nạp.
    static func nsFont(size: CGFloat) -> PlatformFont {
        #if os(macOS)
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.bold],
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == fontFamily { return font }
        let system = NSFont.systemFont(ofSize: size, weight: .bold)
        return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        #else
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: fontFamily,
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        if font.familyName == fontFamily { return font }
        let system = UIFont.systemFont(ofSize: size, weight: .bold)
        return system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? system
        #endif
    }
}

extension Font {
    static func baloo(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(Theme.fontFamily, size: size).weight(weight)
    }
}

extension Color {
    static func player(_ color: PlayerColor) -> Color { Color(platform: Theme.color(color)) }
    static let tableTop = Color(platform: Theme.tableTop)
    static let tableBottom = Color(platform: Theme.tableBottom)
    static let panel = Color(platform: PlatformColor(srgbRed: 0.99, green: 0.97, blue: 0.92, alpha: 1))
    static let ink = Color(platform: Theme.ink)
}

/// Nền bàn chơi dùng cho mọi màn hình.
struct TableBackground: View {
    var body: some View {
        LinearGradient(colors: [.tableTop, .tableBottom], startPoint: .top, endPoint: .bottom)
            .overlay(RadialGradient(colors: [.white.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 700))
            .ignoresSafeArea()
    }
}

/// Nút lớn bo tròn có "độ dày", dùng thống nhất trong menu và màn chơi.
struct ChunkyButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.baloo(20, .bold))
            .foregroundStyle(prominent ? Color.white : Color.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? tint : Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: pressed ? 1 : 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(prominent ? 0.35 : 0), lineWidth: 1.5)
            }
            .offset(y: pressed ? 4 : 0)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension AIDifficulty {
    var title: String {
        switch self {
        case .easy: L("Dễ", "Easy")
        case .normal: L("Thường", "Normal")
        case .hard: L("Khó", "Hard")
        }
    }

    var summary: String {
        switch self {
        case .easy: L("Đi gần như ngẫu nhiên. Hợp để làm quen.", "Moves almost at random. Good for learning the game.")
        case .normal: L("Biết đá quân, ra quân và né nguy hiểm, nhưng đôi lúc tính sai.", "Captures, releases pieces and avoids danger, but sometimes misjudges.")
        case .hard: L("Tính kỹ khả năng bị đá và cơ hội đá quân ở từng nước.", "Weighs the risk of being captured and the chance to capture on every move.")
        }
    }
}
