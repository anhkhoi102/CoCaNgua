import CoreGraphics

/// Phép chiếu phối cảnh cho bàn cờ 2.5D: bàn nằm ngang, máy quay nhìn chếch từ trên xuống.
///
/// Toạ độ lưới: x sang phải, y xuống dưới (hàng 0 ở xa người nhìn), đơn vị là ô; `height` là độ cao trên mặt bàn.
/// Điểm ở xa được vẽ cao hơn trên màn hình và nhỏ hơn một chút.
struct BoardProjection {
    /// Góc ngẩng của máy quay so với mặt bàn (90° là nhìn thẳng từ trên xuống).
    static let elevation: CGFloat = 50 * .pi / 180
    /// Khoảng cách từ máy quay tới tâm bàn, tính bằng ô. Càng lớn thì phối cảnh càng nhẹ.
    static let distance: CGFloat = 34

    /// Vị trí tâm bàn trên màn hình.
    var center: CGPoint = .zero
    /// Số điểm ảnh của một ô tại tâm bàn.
    var unit: CGFloat = 40

    private static let half = CGFloat(BoardLayout.gridSize) / 2

    /// Hệ số thu phóng tại một điểm (1 ở tâm bàn, lớn hơn ở gần, nhỏ hơn ở xa).
    func scale(at grid: CGPoint, height: CGFloat = 0) -> CGFloat {
        let depth = Self.half - grid.y
        return Self.distance / (Self.distance + depth * cos(Self.elevation) - height * sin(Self.elevation))
    }

    func point(_ grid: CGPoint, height: CGFloat = 0) -> CGPoint {
        let across = grid.x - Self.half
        let depth = Self.half - grid.y
        let s = scale(at: grid, height: height)
        let up = depth * sin(Self.elevation) + height * cos(Self.elevation)
        return CGPoint(x: center.x + across * s * unit, y: center.y + up * s * unit)
    }

    /// Chiếu một hình vẽ trong toạ độ lưới lên màn hình. Đường cong được chia nhỏ thành đoạn thẳng trước khi chiếu.
    func path(_ gridPath: CGPath, height: CGFloat = 0) -> CGPath {
        let result = CGMutablePath()
        gridPath.flattened(threshold: 0.02).applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: result.move(to: point(points[0], height: height))
            case .addLineToPoint: result.addLine(to: point(points[0], height: height))
            case .closeSubpath: result.closeSubpath()
            default: break
            }
        }
        return result
    }

    /// Chọn `unit` và `center` sao cho toàn bộ bàn (kể cả bề dày và chỗ cho quân đứng ở hàng xa nhất) nằm gọn trong `size`.
    static func fitting(size: CGSize, margin: CGFloat, outset: CGFloat, thickness: CGFloat, headroom: CGFloat) -> BoardProjection {
        var probe = BoardProjection(center: .zero, unit: 1)
        let grid = CGFloat(BoardLayout.gridSize)
        let corners = [CGPoint(x: -outset, y: -outset), CGPoint(x: grid + outset, y: -outset),
                       CGPoint(x: -outset, y: grid + outset), CGPoint(x: grid + outset, y: grid + outset)]
        var points = corners.map { probe.point($0) } + corners.map { probe.point($0, height: -thickness) }
        points += corners.prefix(2).map { probe.point($0, height: headroom) }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 1
        let unit = max(4, min((size.width - 2 * margin) / (maxX - minX), (size.height - 2 * margin) / (maxY - minY)))
        probe.unit = unit
        probe.center = CGPoint(x: size.width / 2 - (minX + maxX) / 2 * unit, y: size.height / 2 - (minY + maxY) / 2 * unit)
        return probe
    }
}
