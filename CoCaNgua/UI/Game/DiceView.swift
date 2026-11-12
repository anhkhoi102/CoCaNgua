import SwiftUI

/// Viên xúc xắc. Chỉ hiển thị mặt được truyền vào; không tự sinh kết quả.
struct DiceView: View {
    var face: Int
    var tilt: Double
    var rolling: Bool
    var tint: Color
    var size: CGFloat = 92

    private static let pips: [Int: [(Int, Int)]] = [
        1: [(1, 1)],
        2: [(0, 0), (2, 2)],
        3: [(0, 0), (1, 1), (2, 2)],
        4: [(0, 0), (2, 0), (0, 2), (2, 2)],
        5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
        6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(tint)
                .offset(y: size * 0.07)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(tint, lineWidth: size * 0.05)
            Canvas { context, canvasSize in
                let step = canvasSize.width / 4
                let radius = canvasSize.width * 0.085
                for (column, row) in Self.pips[face] ?? [] {
                    let center = CGPoint(x: step * CGFloat(column + 1), y: step * CGFloat(row + 1))
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(face == 1 ? Color.player(.red) : .ink))
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt))
        .scaleEffect(rolling ? 1.12 : 1)
        .offset(y: rolling ? -8 : 0)
        .animation(.spring(response: 0.18, dampingFraction: 0.55), value: tilt)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: rolling)
        .accessibilityLabel(Text(L("Xúc xắc: \(face)", "Die: \(face)")))
    }
}
