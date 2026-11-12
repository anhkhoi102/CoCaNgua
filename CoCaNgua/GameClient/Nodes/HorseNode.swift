import GameCore
import SpriteKit

/// Một quân cờ trên bàn 2.5D: ảnh quân dựng sẵn theo màu người chơi, đứng thẳng trên ô, có vòng sáng quanh đế
/// khi chọn được. Vị trí của node là tâm đế (điểm quân chạm mặt bàn).
///
/// Bóng đổ (`shadow`) không phải node con: cảnh đặt nó vào một lớp riêng nằm dưới mọi quân, để bóng của quân này
/// không bao giờ vẽ đè lên thân quân khác, và gọi `updateShadow()` mỗi khung hình.
@MainActor
final class HorseNode: SKNode {
    let horse: HorseID
    private let style: PieceStyle
    let shadow: SKSpriteNode
    private let shadowSprite: PieceShadow.Sprite
    private let ring = SKShapeNode()
    private let body = SKNode()
    private let sprite: SKSpriteNode
    private(set) var pieceHeight: CGFloat = 40

    init(horse: HorseID, style: PieceStyle, texture: SKTexture) {
        self.horse = horse
        self.style = style
        self.sprite = SKSpriteNode(texture: texture)
        self.shadowSprite = PieceShadow.sprite(for: style, piece: texture)
        self.shadow = SKSpriteNode(texture: shadowSprite.texture)
        super.init()
        sprite.anchorPoint = style.baseAnchor
        shadow.anchorPoint = shadowSprite.anchor
        ring.fillColor = PlatformColor(srgbRed: 1.0, green: 0.84, blue: 0.25, alpha: 0.95)
        ring.strokeColor = Theme.ink
        ring.isHidden = true
        addChild(ring)
        addChild(body)
        body.addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) không được hỗ trợ") }

    /// Đặt kích thước theo số điểm ảnh của một ô tại tâm bàn; phối cảnh được áp bằng `setScale` của node.
    func resize(cell: CGFloat) {
        let width = cell * style.widthInCells
        sprite.size = CGSize(width: width, height: width * PieceStyle.aspect)
        pieceHeight = sprite.size.height * (1 - style.baseAnchor.y)
        let flatten = sin(BoardProjection.elevation)
        shadow.size = CGSize(width: width * shadowSprite.relativeSize.width, height: width * shadowSprite.relativeSize.height)
        let ringWidth = cell * 0.90
        ring.path = CGPath(ellipseIn: CGRect(x: -ringWidth / 2, y: -ringWidth * flatten / 2,
                                             width: ringWidth, height: ringWidth * flatten), transform: nil)
        ring.lineWidth = max(1.5, cell * 0.045)
    }

    /// Đặt bóng theo quân. Khi quân được nhấc lên, bóng trượt ra xa theo hướng đèn, nhạt đi và loang rộng hơn.
    func updateShadow() {
        let lift = max(0, body.position.y) * yScale
        let ratio = lift / max(1, pieceHeight * yScale)
        shadow.position = CGPoint(x: position.x + lift * PieceShadow.lean.dx * 1.1, y: position.y + lift * PieceShadow.lean.dy * 0.9)
        shadow.setScale(xScale * (1 + 0.12 * min(ratio, 3)))
        shadow.alpha = alpha / (1 + 0.9 * ratio)
        shadow.isHidden = isHidden || parent == nil
    }

    /// Quân bị đá lộn một vòng quanh đế trong lúc văng về chuồng.
    func tumble(duration: TimeInterval, clockwise: Bool) {
        let spin = SKAction.rotate(byAngle: clockwise ? -2 * .pi : 2 * .pi, duration: duration)
        spin.timingMode = .easeOut
        body.run(.sequence([spin, .rotate(toAngle: 0, duration: 0)]), withKey: "tumble")
    }

    /// Quân có thể chọn sẽ nhún nhẹ và có vòng sáng quanh đế.
    var isSelectable = false {
        didSet {
            guard isSelectable != oldValue else { return }
            ring.isHidden = !isSelectable
            body.removeAction(forKey: "bob")
            ring.removeAction(forKey: "pulse")
            body.setScale(1)
            ring.alpha = 1
            if isSelectable {
                let bob = SKAction.sequence([.scale(to: 1.10, duration: 0.38), .scale(to: 1.0, duration: 0.38)])
                bob.timingMode = .easeInEaseOut
                body.run(.repeatForever(bob), withKey: "bob")
                ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.38), .fadeAlpha(to: 1, duration: 0.38)])), withKey: "pulse")
            }
        }
    }

    /// Quân đang được chọn để xem ô đích: vòng quanh đế chuyển sang trắng.
    var isFocused = false {
        didSet {
            ring.fillColor = isFocused ? PlatformColor.white : PlatformColor(srgbRed: 1.0, green: 0.84, blue: 0.25, alpha: 0.95)
            ring.lineWidth = ring.lineWidth * (isFocused == oldValue ? 1 : (isFocused ? 1.8 : 1 / 1.8))
        }
    }

    /// Nhấc quân lên khỏi mặt bàn rồi hạ xuống trong lúc nhảy sang ô khác (bóng ở lại trên mặt bàn).
    func jump(height: CGFloat, duration: TimeInterval) {
        let up = SKAction.moveBy(x: 0, y: height, duration: duration / 2)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -height, duration: duration / 2)
        down.timingMode = .easeIn
        body.run(.sequence([up, down, .move(to: .zero, duration: 0)]), withKey: "jump")
    }

    /// Nhún nhẹ khi quân đáp xuống ô mới.
    func land(duration: TimeInterval) {
        let squash = SKAction.group([.scaleX(to: 1.10, duration: duration * 0.35), .scaleY(to: 0.86, duration: duration * 0.35)])
        let stretch = SKAction.group([.scaleX(to: 0.97, duration: duration * 0.35), .scaleY(to: 1.05, duration: duration * 0.35)])
        let settle = SKAction.scale(to: 1, duration: duration * 0.30)
        squash.timingMode = .easeOut
        settle.timingMode = .easeOut
        body.run(.sequence([squash, stretch, settle]), withKey: "land")
    }
}
