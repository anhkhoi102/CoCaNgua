import SpriteKit

/// Ảnh bóng đổ của một kiểu quân, tạo một lần từ chính hình dáng quân.
///
/// Gồm hai phần chồng lên nhau: bóng ngả (hình quân ép dẹt và xô nghiêng theo hướng đèn chính trong Tools/, mép mờ)
/// và bóng tiếp xúc (vệt tối mềm ngay dưới đế). Bóng dùng chung cho cả bốn màu vì hình dáng giống nhau.
@MainActor
enum PieceShadow {
    struct Sprite {
        let texture: SKTexture
        /// Kích thước ảnh bóng tính theo bề rộng ảnh quân (1 = rộng bằng ảnh quân).
        let relativeSize: CGSize
        /// Điểm trong ảnh bóng trùng với tâm đế quân.
        let anchor: CGPoint
    }

    /// Đèn chính chiếu từ phía trước bên trái nên bóng ngả về phía sau bên phải; trên màn hình là sang phải và lên trên.
    static let lean = CGVector(dx: 0.42, dy: 0.40)

    private static var cache: [PieceStyle: Sprite] = [:]

    static func sprite(for style: PieceStyle, piece: SKTexture) -> Sprite {
        if let cached = cache[style] { return cached }
        let made = make(style: style, piece: piece.cgImage())
        cache[style] = made
        return made
    }

    private static func make(style: PieceStyle, piece: CGImage) -> Sprite {
        // Bóng vốn mờ nên dựng ở nửa độ phân giải của ảnh quân.
        let scale: CGFloat = 0.5
        let pieceSize = CGSize(width: CGFloat(piece.width) * scale, height: CGFloat(piece.height) * scale)
        let canvas = CGSize(width: (pieceSize.width * 1.72).rounded(), height: (pieceSize.height * 0.64).rounded())
        let anchor = CGPoint(x: pieceSize.width * 0.54, y: pieceSize.height * 0.19)
        let pieceAnchor = CGPoint(x: pieceSize.width * style.baseAnchor.x, y: pieceSize.height * style.baseAnchor.y)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Sprite(texture: SKTexture(), relativeSize: .zero, anchor: CGPoint(x: 0.5, y: 0.5))
        }

        // Bóng ngả: vẽ hình quân ra ngoài khung và chỉ giữ lại phần bóng mờ mà CoreGraphics tạo cho nó.
        let far = canvas.width * 3
        context.saveGState()
        context.setShadow(offset: CGSize(width: far, height: 0), blur: pieceSize.width * 0.045, color: PlatformColor.black.withAlphaComponent(0.36).cgColor)
        context.translateBy(x: anchor.x - far, y: anchor.y)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: lean.dx, d: lean.dy, tx: 0, ty: 0))
        context.translateBy(x: -pieceAnchor.x, y: -pieceAnchor.y)
        context.draw(piece, in: CGRect(origin: .zero, size: pieceSize))
        context.restoreGState()

        // Bóng tiếp xúc: đậm ở giữa đế, tan dần ra ngoài.
        let radius = 0.31 / style.widthInCells * pieceSize.width
        let colors = [PlatformColor.black.withAlphaComponent(0.50).cgColor, PlatformColor.black.withAlphaComponent(0.26).cgColor, PlatformColor.black.withAlphaComponent(0).cgColor]
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1]) {
            context.saveGState()
            context.translateBy(x: anchor.x + radius * 0.10, y: anchor.y + radius * 0.02)
            context.scaleBy(x: 1, y: 0.62)
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
            context.restoreGState()
        }

        guard let image = context.makeImage() else {
            return Sprite(texture: SKTexture(), relativeSize: .zero, anchor: CGPoint(x: 0.5, y: 0.5))
        }
        return Sprite(texture: SKTexture(cgImage: image),
                      relativeSize: CGSize(width: canvas.width / pieceSize.width, height: canvas.height / pieceSize.width),
                      anchor: CGPoint(x: anchor.x / canvas.width, y: anchor.y / canvas.height))
    }
}
