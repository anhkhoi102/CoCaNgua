import CoreGraphics
import GameCore

/// Kiểu quân cờ. Cả hai kiểu đều là ảnh dựng từ hình khối 3D, cùng góc nhìn với bàn cờ.
enum PieceStyle: String, CaseIterable, Identifiable, Sendable {
    /// Quân mã cờ vua (giống quân cờ cá ngựa truyền thống).
    case knight
    /// Quân kiểu Ludo hình cá ngựa.
    case seahorse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knight: L("Mẫu 1", "Style 1")
        case .seahorse: L("Mẫu 2", "Style 2")
        }
    }

    var atlasName: String {
        switch self {
        case .knight: "Knights"
        case .seahorse: "Seahorses"
        }
    }

    func imageName(for color: PlayerColor) -> String {
        let suffix = switch color {
        case .red: "red"
        case .blue: "blue"
        case .green: "green"
        case .yellow: "yellow"
        }
        return "\(rawValue)_\(suffix)"
    }

    /// Vị trí tâm đế trong ảnh (tỉ lệ, gốc ở góc dưới trái), theo cách dựng trong Tools/.
    var baseAnchor: CGPoint {
        switch self {
        case .knight: CGPoint(x: 0.5, y: 0.235)
        case .seahorse: CGPoint(x: 0.5, y: 0.19)
        }
    }

    /// Bề rộng ảnh quân tính theo số ô, chọn sao cho đế quân rộng chưa tới nửa ô và quân cao khoảng 1,2 ô.
    var widthInCells: CGFloat {
        switch self {
        case .knight: 1.18
        case .seahorse: 0.92
        }
    }

    /// Ảnh quân có tỉ lệ 3:4.
    static let aspect: CGFloat = 4.0 / 3.0
}
