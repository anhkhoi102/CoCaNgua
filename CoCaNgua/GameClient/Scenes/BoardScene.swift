import GameCore
import SpriteKit

/// Cảnh bàn cờ 2.5D. Chỉ hiển thị và diễn hoạt những gì `GameEngine` đã quyết định; không chứa luật chơi.
///
/// Mọi hình trên bàn được vẽ trong toạ độ lưới 15×15 rồi chiếu qua `BoardProjection`, nên bàn giữ đúng
/// tỉ lệ và quân luôn khớp với ô khi cửa sổ đổi kích thước.
@MainActor
final class BoardScene: SKScene {
    /// Gọi khi người chơi đã chọn xong một nước (quân và cách dùng xúc xắc).
    var onMoveChosen: ((Move) -> Void)?
    var durationScale = 1.0
    var effectsEnabled = true

    private let rules: RulesConfiguration
    private let pieceStyle: PieceStyle
    private let layout: OrientedBoardLayout
    /// Chứa mọi lớp của bàn; cảnh zoom khi đá quân phóng to và dời node này (không dùng SKCameraNode để ảnh chụp
    /// bằng `SKView.texture(from:)` vẫn thấy đúng).
    private let world = SKNode()
    private let boardLayer = SKNode()
    private let shadowLayer = SKNode()
    private let markerLayer = SKNode()
    private let pieceLayer = SKNode()
    private let effectLayer = SKNode()
    private var horses: [HorseID: HorseNode] = [:]
    private var positions: [HorseID: HorsePosition] = [:]
    private var selectable: [HorseID: [Move]] = [:]  // các nước của từng quân
    /// Quân đang được chọn để xem các ô đích (khi quân đó có nhiều hơn một nước).
    private var focused: HorseID?
    private var projection = BoardProjection()
    /// Kích thước cảnh ở lần dựng bàn gần nhất; bàn chỉ được dựng lại khi kích thước thật sự đổi.
    private var laidOutSize = CGSize.zero
    private let atlas: SKTextureAtlas
    private lazy var sparkTexture = Self.makeSparkTexture()

    // Kích thước theo đơn vị ô.
    private static let outset: CGFloat = 0.45        // viền bàn quanh lưới
    private static let thickness: CGFloat = 0.55     // bề dày tấm bàn
    private static let tileHeight: CGFloat = 0.09    // độ nổi của ô cờ
    private static let stableHeight: CGFloat = 0.16  // độ nổi của chuồng
    private static let headroom: CGFloat = 1.5       // chỗ cho quân đứng ở hàng xa nhất

    private var unit: CGFloat { projection.unit }

    /// `viewpoint`: màu có chuồng được xoay về góc gần người nhìn (màu của người chơi trên máy này).
    init(rules: RulesConfiguration, pieceStyle: PieceStyle, viewpoint: PlayerColor? = nil) {
        self.rules = rules
        self.layout = OrientedBoardLayout(viewpoint: viewpoint)
        self.pieceStyle = pieceStyle
        self.atlas = SKTextureAtlas(named: pieceStyle.atlasName)
        super.init(size: CGSize(width: 800, height: 800))
        scaleMode = .resizeFill
        backgroundColor = .clear
        boardLayer.zPosition = 0
        markerLayer.zPosition = 5
        pieceLayer.zPosition = 10
        shadowLayer.zPosition = 6
        effectLayer.zPosition = 60
        addChild(world)
        [boardLayer, markerLayer, shadowLayer, pieceLayer, effectLayer].forEach(world.addChild)
        relayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) không được hỗ trợ") }

    override func didMove(to view: SKView) {
        // Lần dựng đầu xảy ra trước khi cảnh có view nên chưa gộp được bàn thành ảnh; dựng lại ở đây.
        relayout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // SpriteKit gọi hàm này cả khi kích thước không đổi (mỗi lần SwiftUI cập nhật). Dựng lại bàn gồm vài trăm
        // hình nên chỉ làm khi cần.
        guard size != laidOutSize else { return }
        relayout()
    }

    #if DEBUG
    /// Khoảng cách giữa các khung hình gần đây (giây), để Scripts/snapshot.sh báo tốc độ khung hình.
    private(set) var frameIntervals: [TimeInterval] = []
    private var lastFrameTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        if lastFrameTime > 0 { frameIntervals.append(currentTime - lastFrameTime) }
        lastFrameTime = currentTime
    }

    func resetFrameIntervals() { frameIntervals = [] }
    #endif

    override func didEvaluateActions() {
        for node in horses.values { node.updateShadow() }
    }

    // MARK: - Bố cục

    private func relayout() {
        guard size.width > 10, size.height > 10 else { return }
        laidOutSize = size
        world.removeAllActions()
        world.setScale(1)
        world.position = .zero
        projection = BoardProjection.fitting(size: size, margin: 10, outset: Self.outset,
                                             thickness: Self.thickness, headroom: Self.headroom)
        drawBoard()
        bakeBoard()
        horses.values.forEach { $0.resize(cell: unit) }
        placeAll(animated: false)
        drawMarkers()
    }

    /// Gộp vài trăm hình của bàn cờ thành một ảnh duy nhất. Bàn là phần tĩnh; nếu để nguyên từng hình thì SpriteKit
    /// phải vẽ lại tất cả ở mỗi khung hình và tốc độ khung hình tụt mạnh.
    private func bakeBoard() {
        guard let view, let texture = view.texture(from: boardLayer, crop: CGRect(origin: .zero, size: size)) else { return }
        boardLayer.removeAllChildren()
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = .zero
        sprite.position = .zero
        sprite.size = size
        boardLayer.addChild(sprite)
    }

    /// Tâm đế của một quân tại vị trí cho trước, và hệ số phối cảnh ở đó.
    private func placement(for position: HorsePosition, horse: HorseID) -> (point: CGPoint, scale: CGFloat) {
        let grid = layout.gridPoint(for: position, horse: horse)
        let height = position.isStable ? Self.stableHeight : Self.tileHeight
        return (projection.point(grid, height: height), projection.scale(at: grid, height: height))
    }

    // MARK: - Vẽ bàn

    private func drawBoard() {
        boardLayer.removeAllChildren()
        let grid = CGFloat(BoardLayout.gridSize)
        let outer = CGRect(x: -Self.outset, y: -Self.outset, width: grid + 2 * Self.outset, height: grid + 2 * Self.outset)
        let outerPath = CGPath(roundedRect: outer, cornerWidth: 0.9, cornerHeight: 0.9, transform: nil)

        // Bóng dưới bàn, rồi thân tấm bàn (nhiều lớp chồng để tạo bề dày), rồi mặt bàn.
        let shadow = SKShapeNode(path: projection.path(outerPath, height: -Self.thickness - 0.5))
        shadow.fillColor = PlatformColor.black.withAlphaComponent(0.30)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -unit * 0.12)
        boardLayer.addChild(shadow)
        extrude(outerPath, from: -Self.thickness, to: 0, side: Theme.boardEdge.blended(withFraction: 0.25, of: .black) ?? Theme.boardEdge,
                top: Theme.board, stroke: Theme.boardEdge, lineWidth: unit * 0.08, layers: 10)

        for color in PlayerColor.allCases { drawStable(color) }

        let safe = Board.safeSquares(for: rules.safeSquares)
        for (index, gridCell) in layout.track.enumerated() {
            var fill = Theme.cell
            var stroke = Theme.cellStroke
            var textColor: PlatformColor?
            for color in PlayerColor.allCases {
                if index == Board.startSquare(of: color) {
                    fill = Theme.color(color)
                    stroke = Theme.darkColor(color)
                    textColor = .white
                } else if index == Board.mouthSquare(of: color) {
                    fill = Theme.lightColor(color)
                    stroke = Theme.color(color)
                }
            }
            drawTile(gridCell, fill: fill, stroke: stroke)
            if safe.contains(index) { drawLabel("★", in: gridCell, color: textColor ?? Theme.cellStroke) }
        }

        for color in PlayerColor.allCases {
            for rung in 1...Board.homeRungs {
                let gridCell = layout.homeCell(rung: rung, color: color)
                drawTile(gridCell, fill: Theme.color(color), stroke: Theme.darkColor(color))
                drawLabel("\(rung)", in: gridCell, color: PlatformColor.white.withAlphaComponent(0.92))
            }
        }
        drawCenter()
    }

    /// Vẽ một hình có bề dày: các lớp cạnh màu `side` từ độ cao `bottom` lên `top`, rồi mặt trên.
    private func extrude(_ gridPath: CGPath, from bottom: CGFloat, to top: CGFloat, side: PlatformColor, top fill: PlatformColor,
                         stroke: PlatformColor = .clear, lineWidth: CGFloat = 0, layers: Int = 3) {
        for layer in 0..<layers {
            let height = bottom + (top - bottom) * CGFloat(layer) / CGFloat(layers)
            let node = SKShapeNode(path: projection.path(gridPath, height: height))
            node.fillColor = side
            node.strokeColor = side
            node.lineWidth = 1
            boardLayer.addChild(node)
        }
        let face = SKShapeNode(path: projection.path(gridPath, height: top))
        face.fillColor = fill
        face.strokeColor = stroke
        face.lineWidth = lineWidth
        face.lineJoin = .round
        boardLayer.addChild(face)
    }

    private func drawTile(_ gridCell: GridCell, fill: PlatformColor, stroke: PlatformColor) {
        let rect = CGRect(x: CGFloat(gridCell.column), y: CGFloat(gridCell.row), width: 1, height: 1).insetBy(dx: 0.06, dy: 0.06)
        let path = CGPath(roundedRect: rect, cornerWidth: 0.2, cornerHeight: 0.2, transform: nil)
        extrude(path, from: 0, to: Self.tileHeight, side: stroke, top: fill, stroke: stroke, lineWidth: max(1, unit * 0.03), layers: 2)
    }

    private func drawLabel(_ text: String, in gridCell: GridCell, color: PlatformColor) {
        let center = CGPoint(x: CGFloat(gridCell.column) + 0.5, y: CGFloat(gridCell.row) + 0.5)
        let scale = projection.scale(at: center, height: Self.tileHeight)
        let node = SKLabelNode()
        node.attributedText = NSAttributedString(string: text, attributes: [.font: Theme.nsFont(size: unit * 0.52 * scale), .foregroundColor: color])
        node.verticalAlignmentMode = .center
        node.horizontalAlignmentMode = .center
        node.position = projection.point(center, height: Self.tileHeight)
        // Ép dẹt theo chiều dọc để chữ trông như nằm trên mặt bàn.
        node.yScale = sin(BoardProjection.elevation)
        boardLayer.addChild(node)
    }

    private func drawStable(_ color: PlayerColor) {
        let middle = layout.stableCenter(of: color)
        let area = CGRect(x: middle.x - 3, y: middle.y - 3, width: 6, height: 6).insetBy(dx: 0.30, dy: 0.30)
        extrude(CGPath(roundedRect: area, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil), from: 0, to: Self.stableHeight,
                side: Theme.darkColor(color), top: Theme.color(color), stroke: Theme.darkColor(color), lineWidth: unit * 0.05, layers: 3)
        let yard = SKShapeNode(path: projection.path(CGPath(roundedRect: area.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil),
                                                     height: Self.stableHeight))
        yard.fillColor = Theme.lightColor(color)
        yard.strokeColor = Theme.darkColor(color).withAlphaComponent(0.35)
        yard.lineWidth = max(1, unit * 0.03)
        boardLayer.addChild(yard)
        for index in 0..<Board.horsesPerPlayer {
            let center = layout.stableSlot(of: color, index: index)
            let circle = CGPath(ellipseIn: CGRect(x: center.x - 0.52, y: center.y - 0.52, width: 1.04, height: 1.04), transform: nil)
            let slot = SKShapeNode(path: projection.path(circle, height: Self.stableHeight))
            slot.fillColor = PlatformColor.white.withAlphaComponent(0.85)
            slot.strokeColor = Theme.color(color)
            slot.lineWidth = max(1.5, unit * 0.05)
            boardLayer.addChild(slot)
        }
    }

    private func drawCenter() {
        let cell = layout.center
        let frame = CGRect(x: CGFloat(cell.column), y: CGFloat(cell.row), width: 1, height: 1).insetBy(dx: 0.03, dy: 0.03)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        // Trong toạ độ lưới, y nhỏ là phía xa (phía Đỏ), y lớn là phía gần (phía Xanh lá).
        let corners: [PlayerColor: (CGPoint, CGPoint)] = [
            .red: (CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY)),
            .blue: (CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.minY)),
            .green: (CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)),
            .yellow: (CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY)),
        ]
        for (color, (a, b)) in corners {
            let path = CGMutablePath()
            path.move(to: center)
            path.addLine(to: layout.point(a))
            path.addLine(to: layout.point(b))
            path.closeSubpath()
            let triangle = SKShapeNode(path: projection.path(path, height: Self.tileHeight))
            triangle.fillColor = Theme.color(color)
            triangle.strokeColor = Theme.board
            triangle.lineWidth = max(1, unit * 0.03)
            boardLayer.addChild(triangle)
        }
    }

    // MARK: - Quân

    /// Đặt mọi quân đúng theo trạng thái, không diễn hoạt.
    func sync(with state: GameState) {
        var seen = Set<HorseID>()
        for player in state.players {
            for (index, position) in player.horses.enumerated() {
                let id = HorseID(player.color, index)
                seen.insert(id)
                if horses[id] == nil {
                    let node = HorseNode(horse: id, style: pieceStyle, texture: atlas.textureNamed(pieceStyle.imageName(for: id.color)))
                    node.resize(cell: unit)
                    horses[id] = node
                    pieceLayer.addChild(node)
                    shadowLayer.addChild(node.shadow)
                }
                positions[id] = position
                horses[id]?.alpha = player.status == .active ? 1 : 0.35
            }
        }
        for (id, node) in horses where !seen.contains(id) {
            node.removeFromParent()
            node.shadow.removeFromParent()
            horses[id] = nil
            positions[id] = nil
        }
        placeAll(animated: false)
    }

    /// Vị trí đích của từng quân, có dàn ra khi nhiều quân chung một ô.
    private func targets() -> [HorseID: (point: CGPoint, scale: CGFloat)] {
        var result: [HorseID: (CGPoint, CGFloat)] = [:]
        let groups = Dictionary(grouping: positions.keys) { id -> String in
            switch positions[id]! {
            case .stable: "s\(id.color.rawValue)-\(id.index)"
            case .track(let square): "t\(square)"
            case .home(let rung): "h\(id.color.rawValue)-\(rung)"
            }
        }
        for group in groups.values {
            let sorted = group.sorted { ($0.color.rawValue, $0.index) < ($1.color.rawValue, $1.index) }
            for (order, id) in sorted.enumerated() {
                var target = placement(for: positions[id]!, horse: id)
                let spread = CGFloat(order) - CGFloat(sorted.count - 1) / 2
                target.point.x += spread * unit * 0.36 * target.scale
                target.point.y -= spread * unit * 0.10 * target.scale
                result[id] = (target.point, target.scale * (sorted.count > 1 ? 0.82 : 1))
            }
        }
        return result
    }

    /// Quân ở gần người nhìn (thấp hơn trên màn hình) được vẽ đè lên quân ở xa.
    private func depthOrder(_ point: CGPoint) -> CGFloat {
        10 - point.y / max(1, size.height)
    }

    private func placeAll(animated: Bool) {
        for (id, target) in targets() {
            guard let node = horses[id] else { continue }
            node.zPosition = depthOrder(target.point)
            if animated {
                let action = SKAction.group([.move(to: target.point, duration: 0.18 * durationScale), .scale(to: target.scale, duration: 0.18 * durationScale)])
                action.timingMode = .easeOut
                node.run(action)
            } else {
                node.removeAllActions()
                node.position = target.point
                node.setScale(target.scale)
            }
        }
        // Hoạt ảnh vừa bị gỡ sẽ không bao giờ báo xong; phải tự báo, nếu không vòng lặp ván chờ mãi.
        if !animated { finishPendingActions() }
    }

    // MARK: - Chờ hoạt ảnh

    /// Các hoạt ảnh đang có người chờ. SpriteKit không gọi hàm hoàn tất khi một hoạt ảnh bị gỡ giữa chừng
    /// (cảnh dựng lại do đổi kích thước cửa sổ, quay lại từ ứng dụng khác…), nên cảnh tự giữ danh sách để báo xong thay.
    private var pendingActions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextPendingAction = 0

    /// Chạy hoạt ảnh và chờ tới khi nó xong hoặc bị huỷ. Luôn trả về, kể cả khi hoạt ảnh bị gỡ.
    private func perform(_ action: SKAction, on node: SKNode) async {
        // Cảnh chưa được hiển thị thì SpriteKit không chạy hoạt ảnh: không chờ, vị trí sẽ được đặt lại khi đồng bộ.
        guard view != nil else { return }
        nextPendingAction += 1
        let token = nextPendingAction
        await withCheckedContinuation { continuation in
            pendingActions[token] = continuation
            node.run(action) { [weak self] in self?.pendingActions.removeValue(forKey: token)?.resume() }
        }
    }

    private func finishPendingActions() {
        let waiting = pendingActions.values
        pendingActions = [:]
        waiting.forEach { $0.resume() }
    }

    // MARK: - Chọn quân

    /// Đánh dấu các quân người chơi có thể chọn và ô đích của chúng. Truyền mảng rỗng để bỏ đánh dấu.
    func setSelectable(_ moves: [Move]) {
        selectable = Dictionary(grouping: moves, by: \.horse)
        focused = nil
        for (id, node) in horses { node.isSelectable = selectable[id] != nil }
        drawMarkers()
    }

    /// Chọn một quân để hiện các ô đích của riêng nó (dùng khi quân có nhiều nước). `nil` = bỏ chọn.
    func focus(_ horse: HorseID?) {
        focused = horse.flatMap { selectable[$0] == nil ? nil : $0 }
        drawMarkers()
    }

    private func markerCenter(_ move: Move) -> CGPoint {
        projection.point(layout.gridPoint(for: move.to, horse: move.horse), height: Self.tileHeight + 0.01)
    }

    private func markerLabel(_ move: Move) -> String {
        switch move.use {
        case .fly: "✈"
        case .die, .sum: "\(move.roll)"
        }
    }

    private func drawMarkers() {
        markerLayer.removeAllChildren()
        let moves = focused.flatMap { selectable[$0] } ?? selectable.values.flatMap { $0 }
        let showLabels = focused != nil
        for move in moves {
            let grid = layout.gridPoint(for: move.to, horse: move.horse)
            let color = Theme.color(move.horse.color)
            // Ô đích trống: chấm tròn màu người đi. Ô có quân đối phương: vòng lớn dưới đế quân sắp bị đá.
            let radius: CGFloat = move.captures.isEmpty ? (showLabels ? 0.36 : 0.24) : 0.46
            let circle = CGPath(ellipseIn: CGRect(x: grid.x - radius, y: grid.y - radius, width: radius * 2, height: radius * 2), transform: nil)
            let marker = SKShapeNode(path: projection.path(circle, height: Self.tileHeight + 0.01))
            marker.fillColor = color.withAlphaComponent(move.captures.isEmpty ? (showLabels ? 0.85 : 0.38) : 0.60)
            marker.strokeColor = move.captures.isEmpty ? (showLabels ? Theme.ink : color) : Theme.ink
            marker.lineWidth = max(2, unit * (showLabels ? 0.05 : 0.06))
            marker.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])))
            markerLayer.addChild(marker)
            if showLabels {
                // Nhãn cho biết nước này dùng gì (số bước hoặc bay), trên nền tối để đọc được trên mọi ô.
                let scale = projection.scale(at: grid, height: Self.tileHeight)
                var position = markerCenter(move)
                // Ô đích đang có quân (nước đá quân): đưa nhãn lên phía trên quân đó để không bị che.
                if !move.captures.isEmpty { position.y += unit * 1.45 * scale }
                let badge = SKShapeNode(circleOfRadius: unit * 0.27 * scale)
                badge.fillColor = Theme.ink
                badge.strokeColor = .white
                badge.lineWidth = max(1.5, unit * 0.04)
                badge.position = position
                badge.zPosition = 40
                let label = SKLabelNode()
                label.attributedText = NSAttributedString(string: markerLabel(move), attributes: [
                    .font: Theme.nsFont(size: unit * 0.34 * scale), .foregroundColor: PlatformColor.white,
                ])
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                badge.addChild(label)
                markerLayer.addChild(badge)
            }
        }
        for (id, node) in horses { node.isFocused = id == focused }
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        handleTap(at: event.location(in: world))
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { handleTap(at: touch.location(in: world)) }
    }
    #endif

    /// Ngón tay che mất quân và kém chính xác hơn con trỏ nên vùng bấm trên iPhone rộng hơn.
    private static let tapReach: CGFloat = Device.isPhone ? 1.35 : 1

    private func handleTap(at location: CGPoint) {
        // Đã chọn quân: bấm vào một ô đích của nó để đi.
        if let focused, let options = selectable[focused] {
            let hit = options
                .map { move -> (Move, CGFloat) in
                    let center = markerCenter(move)
                    var distance = hypot(center.x - location.x, (center.y - location.y) * 1.3)
                    if !move.captures.isEmpty {
                        distance = min(distance, hypot(center.x - location.x, center.y + unit * 1.45 - location.y), hypot(center.x - location.x, center.y + unit * 0.7 - location.y))
                    }
                    return (move, distance)
                }
                .filter { $0.1 <= unit * 0.62 * Self.tapReach }
                .min { $0.1 < $1.1 }
            if let hit {
                onMoveChosen?(hit.0)
                return
            }
        }
        // Quân đứng thẳng nên vùng bấm là quanh thân quân, không chỉ quanh đế.
        let hit = selectable.keys
            .compactMap { id -> (HorseID, CGFloat)? in
                guard let node = horses[id] else { return nil }
                let body = CGPoint(x: node.position.x, y: node.position.y + node.pieceHeight * node.yScale * 0.38)
                let reach = unit * node.yScale * 0.75 * Self.tapReach
                let distance = hypot(body.x - location.x, (body.y - location.y) * 0.75)
                return distance <= reach ? (id, distance) : nil
            }
            .min { $0.1 < $1.1 }
        guard let horse = hit?.0, let options = selectable[horse] else {
            focus(nil)
            return
        }
        if options.count == 1 {
            onMoveChosen?(options[0])
        } else {
            // Nhiều nước cho quân này (hai viên, cộng điểm, bay): hiện các ô đích để chọn.
            AudioManager.shared.play(.uiClick)
            focus(focused == horse ? nil : horse)
        }
    }

    // MARK: - Hoạt ảnh

    /// Diễn hoạt một nước đi đã được engine chấp nhận.
    func animate(_ move: Move) async {
        guard let node = horses[move.horse] else { return }
        // Nước đá quân: phóng to vào ô sắp xảy ra va chạm ngay trước cú nhảy cuối, rồi thu về khi quân bị đá văng đi.
        let closeUp = !move.captures.isEmpty && effectsEnabled
        if move.kind == .release {
            if closeUp { await zoomIn(on: move, duration: 0.30 * durationScale) }
            AudioManager.shared.play(.release)
            await hop(node, to: move.to, duration: (closeUp ? 0.50 : 0.42) * durationScale, lift: 1.3)
        } else if move.kind == .fly {
            // Bay: một cú nhảy cao, dài tới thẳng ô cửa chuồng. Ống kính áp sát dần trong lúc quân đang bay.
            AudioManager.shared.play(.release)
            if closeUp { Task { await zoomIn(on: move, duration: 0.62 * durationScale) } }
            await hop(node, to: move.to, duration: 0.70 * durationScale, lift: 3.2)
        } else {
            for (index, step) in move.path.enumerated() {
                if closeUp, index == move.path.count - 1 {
                    await zoomIn(on: move, duration: 0.30 * durationScale)
                    await hop(node, to: step, duration: 0.34 * durationScale, lift: 1.0)
                } else {
                    await hop(node, to: step, duration: 0.17 * durationScale, lift: 0.45)
                }
                AudioManager.shared.play(.step)
            }
        }
        positions[move.horse] = move.to
        node.land(duration: 0.22 * durationScale)

        if !move.captures.isEmpty {
            AudioManager.shared.play(.capture)
            burst(at: bodyCenter(of: node), colors: move.captures.map { Theme.color($0.color) }, count: 26)
            impactRing(at: node.position, scale: node.xScale)
            shake()
            // Giữ khoảnh khắc va chạm một nhịp ngắn trước khi quân bị đá văng đi.
            if closeUp { await perform(.wait(forDuration: 0.20 * durationScale), on: self) }
            for (index, captured) in move.captures.enumerated() {
                positions[captured] = .stable
                guard let victim = horses[captured] else { continue }
                victim.zPosition = 45
                let home = placement(for: .stable, horse: captured)
                let duration = (closeUp ? 0.70 : 0.55) * durationScale
                if closeUp, index == 0 { zoomOut(duration: duration) }
                victim.jump(height: unit * 2.4, duration: duration)
                if effectsEnabled { victim.tumble(duration: duration, clockwise: home.point.x > victim.position.x) }
                let fly = SKAction.group([.move(to: home.point, duration: duration), .scale(to: home.scale, duration: duration)])
                fly.timingMode = .easeInEaseOut
                await perform(fly, on: victim)
                victim.land(duration: 0.22 * durationScale)
            }
        } else if move.to.isHome {
            AudioManager.shared.play(.climb)
            burst(at: bodyCenter(of: node), colors: [Theme.color(move.horse.color), .white], count: 22)
        } else {
            AudioManager.shared.play(.land)
        }
        placeAll(animated: true)
    }

    // MARK: - Cảnh zoom khi đá quân

    private static let closeUpScale: CGFloat = 1.9

    /// Phóng to vào ô đích của nước đi. Khung nhìn bị giữ trong phạm vi cảnh nên không lộ ra vùng trống ngoài bàn.
    private func zoomIn(on move: Move, duration: TimeInterval) async {
        let target = placement(for: move.to, horse: move.horse)
        let focus = CGPoint(x: target.point.x, y: target.point.y + unit * 0.55 * target.scale)
        let scale = Self.closeUpScale
        let origin = CGPoint(x: min(0, max(size.width * (1 - scale), size.width / 2 - focus.x * scale)),
                             y: min(0, max(size.height * (1 - scale), size.height / 2 - focus.y * scale)))
        let action = SKAction.group([.move(to: origin, duration: duration), .scale(to: scale, duration: duration)])
        action.timingMode = .easeInEaseOut
        world.removeAction(forKey: "zoom")
        await perform(action, on: world)
    }

    private func zoomOut(duration: TimeInterval) {
        let action = SKAction.group([.move(to: .zero, duration: duration), .scale(to: 1, duration: duration)])
        action.timingMode = .easeInEaseOut
        world.run(action, withKey: "zoom")
    }

    /// Vòng sáng loang ra trên mặt bàn tại chỗ va chạm.
    private func impactRing(at point: CGPoint, scale: CGFloat) {
        guard effectsEnabled else { return }
        let width = unit * 0.9 * scale
        let ring = SKShapeNode(ellipseIn: CGRect(x: -width / 2, y: -width * sin(BoardProjection.elevation) / 2,
                                                 width: width, height: width * sin(BoardProjection.elevation)))
        ring.strokeColor = .white
        ring.fillColor = .clear
        ring.lineWidth = max(2, unit * 0.09)
        ring.position = point
        ring.zPosition = 7
        world.addChild(ring)
        let duration = 0.38 * durationScale
        let grow = SKAction.group([.scale(to: 2.6, duration: duration), .fadeOut(withDuration: duration)])
        grow.timingMode = .easeOut
        ring.run(.sequence([grow, .removeFromParent()]))
    }

    /// Quân nhảy sang một vị trí: đế trượt trên mặt bàn tới đích còn thân quân nhấc lên rồi hạ xuống.
    private func hop(_ node: HorseNode, to position: HorsePosition, duration: TimeInterval, lift: CGFloat) async {
        let target = placement(for: position, horse: node.horse)
        node.zPosition = max(node.zPosition, depthOrder(target.point)) + 0.5
        node.jump(height: unit * lift, duration: duration)
        let move = SKAction.group([.move(to: target.point, duration: duration), .scale(to: target.scale, duration: duration)])
        move.timingMode = .easeInEaseOut
        await perform(move, on: node)
        node.zPosition = depthOrder(target.point)
    }

    private func bodyCenter(of node: HorseNode) -> CGPoint {
        CGPoint(x: node.position.x, y: node.position.y + node.pieceHeight * node.yScale * 0.4)
    }

    private func shake() {
        guard effectsEnabled else { return }
        let amount = unit * 0.10
        pieceLayer.run(.sequence([
            .moveBy(x: amount, y: 0, duration: 0.04), .moveBy(x: -2 * amount, y: 0, duration: 0.06),
            .moveBy(x: amount, y: 0, duration: 0.04),
        ]))
    }

    /// Pháo giấy khi có người thắng.
    func celebrate(winner: PlayerColor) {
        guard effectsEnabled else { return }
        let colors = [Theme.color(winner), .white, Theme.color(.yellow), Theme.lightColor(winner)]
        let grid = CGFloat(BoardLayout.gridSize)
        for index in 0..<6 {
            let delay = Double(index) * 0.22
            let spot = projection.point(CGPoint(x: grid * CGFloat.random(in: 0.15...0.85), y: grid * CGFloat.random(in: 0.2...0.8)), height: 2)
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in self?.burst(at: spot, colors: colors, count: 46, spread: 2.6) }]))
        }
    }

    private func burst(at position: CGPoint, colors: [PlatformColor], count: Int, spread: CGFloat = 1.4) {
        guard effectsEnabled else { return }
        for color in colors {
            let emitter = SKEmitterNode()
            emitter.particleTexture = sparkTexture
            emitter.position = position
            emitter.numParticlesToEmit = max(4, count / colors.count)
            emitter.particleBirthRate = 600
            emitter.particleLifetime = 0.7
            emitter.particleLifetimeRange = 0.35
            emitter.emissionAngleRange = .pi * 2
            emitter.particleSpeed = unit * 3.2 * spread
            emitter.particleSpeedRange = unit * 2.0 * spread
            emitter.yAcceleration = -unit * 7
            emitter.particleScale = unit / 150
            emitter.particleScaleRange = unit / 260
            emitter.particleScaleSpeed = -unit / 320
            emitter.particleAlphaSpeed = -1.2
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .alpha
            effectLayer.addChild(emitter)
            emitter.run(.sequence([.wait(forDuration: 1.6), .removeFromParent()]))
        }
    }

    private static func makeSparkTexture() -> SKTexture {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: 3, y: 3, width: side - 6, height: side - 6))
        return context.makeImage().map { SKTexture(cgImage: $0) } ?? SKTexture()
    }
}
