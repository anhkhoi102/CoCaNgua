import CoreGraphics
import GameCore

/// Một ô trên lưới 15×15 của bàn cờ; hàng 0 ở trên cùng.
struct GridCell: Hashable {
    var column: Int
    var row: Int
}

/// Ánh xạ vị trí logic của GameCore (ô đường chạy, bậc đích, chuồng) sang lưới 15×15.
///
/// Bàn hình chữ thập kiểu Cờ Cá Ngựa: bốn nhánh rộng 3 ô, đường chạy 56 ô đi quanh mép chữ thập theo
/// chiều NGƯỢC kim đồng hồ, làn giữa mỗi nhánh là cột về đích 6 bậc, bốn góc là chuồng.
/// Mỗi màu đi 14 ô: 7 ô dọc nhánh, 6 ô ngang nhánh kế, 1 ô đầu nhánh (ô cửa chuồng của màu kế tiếp).
/// Thứ tự lượt Đỏ → Xanh dương → Xanh lá → Vàng cũng đi ngược kim đồng hồ quanh bàn:
/// Đỏ ở góc trên trái, Xanh dương dưới trái, Xanh lá dưới phải, Vàng trên phải.
enum BoardLayout {
    static let gridSize = 15

    /// Toạ độ lưới của 56 ô đường chạy; chỉ số 0 là ô xuất phát của Đỏ.
    static let track: [GridCell] = {
        var cells: [GridCell] = []
        for row in 0...6 { cells.append(GridCell(column: 6, row: row)) }                               // 0–6: Đỏ xuất phát, đi xuống
        for column in stride(from: 5, through: 0, by: -1) { cells.append(GridCell(column: column, row: 6)) } // 7–12
        cells.append(GridCell(column: 0, row: 7))                                                      // 13: cửa chuồng Xanh dương
        for column in 0...6 { cells.append(GridCell(column: column, row: 8)) }                         // 14–20: Xanh dương xuất phát
        for row in 9...14 { cells.append(GridCell(column: 6, row: row)) }                              // 21–26
        cells.append(GridCell(column: 7, row: 14))                                                     // 27: cửa chuồng Xanh lá
        for row in stride(from: 14, through: 8, by: -1) { cells.append(GridCell(column: 8, row: row)) } // 28–34: Xanh lá xuất phát
        for column in 9...14 { cells.append(GridCell(column: column, row: 8)) }                        // 35–40
        cells.append(GridCell(column: 14, row: 7))                                                     // 41: cửa chuồng Vàng
        for column in stride(from: 14, through: 8, by: -1) { cells.append(GridCell(column: column, row: 6)) } // 42–48: Vàng xuất phát
        for row in stride(from: 5, through: 0, by: -1) { cells.append(GridCell(column: 8, row: row)) } // 49–54
        cells.append(GridCell(column: 7, row: 0))                                                      // 55: cửa chuồng Đỏ
        assert(cells.count == Board.trackLength && Set(cells).count == Board.trackLength)
        return cells
    }()

    static let center = GridCell(column: 7, row: 7)

    /// Ô của bậc đích `rung` (1...6); bậc 6 nằm sát tâm bàn.
    static func homeCell(rung: Int, color: PlayerColor) -> GridCell {
        switch color {
        case .red: GridCell(column: 7, row: rung)
        case .blue: GridCell(column: rung, row: 7)
        case .green: GridCell(column: 7, row: 14 - rung)
        case .yellow: GridCell(column: 14 - rung, row: 7)
        }
    }

    /// Góc 6×6 ô làm chuồng của mỗi màu, cạnh ô xuất phát của màu đó.
    static func stableOrigin(of color: PlayerColor) -> GridCell {
        switch color {
        case .red: GridCell(column: 0, row: 0)
        case .blue: GridCell(column: 0, row: 9)
        case .green: GridCell(column: 9, row: 9)
        case .yellow: GridCell(column: 9, row: 0)
        }
    }

    /// Tâm chỗ đứng trong chuồng của quân thứ `index`, tính theo đơn vị ô (có phần lẻ).
    static func stableSlot(of color: PlayerColor, index: Int) -> CGPoint {
        let origin = stableOrigin(of: color)
        let offsets: [CGPoint] = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)]
        let offset = offsets[index % offsets.count]
        return CGPoint(x: CGFloat(origin.column) + 3 + offset.x * 1.05, y: CGFloat(origin.row) + 3 + offset.y * 1.05)
    }

    /// Tâm của một vị trí quân, theo đơn vị ô (x sang phải, y xuống dưới).
    static func gridPoint(for position: HorsePosition, horse: HorseID) -> CGPoint {
        switch position {
        case .stable:
            return stableSlot(of: horse.color, index: horse.index)
        case .track(let square):
            let cell = track[square]
            return CGPoint(x: CGFloat(cell.column) + 0.5, y: CGFloat(cell.row) + 0.5)
        case .home(let rung):
            let cell = homeCell(rung: rung, color: horse.color)
            return CGPoint(x: CGFloat(cell.column) + 0.5, y: CGFloat(cell.row) + 0.5)
        }
    }
}

/// Bàn cờ đã xoay để chuồng của một màu nằm ở góc gần người nhìn (dưới trái). Chỉ là chuyện hiển thị: xoay nguyên
/// cả bàn theo từng góc phần tư nên chiều đi và thứ tự các màu quanh bàn không đổi.
struct OrientedBoardLayout {
    /// Số lần xoay 90° ngược chiều kim đồng hồ so với `BoardLayout`.
    let turns: Int

    /// `viewpoint` là màu được đưa về góc dưới trái; `nil` giữ nguyên bố cục gốc (Đỏ ở góc trên trái).
    init(viewpoint: PlayerColor? = nil) {
        guard let viewpoint, let index = PlayerColor.allCases.firstIndex(of: viewpoint) else {
            turns = 0
            return
        }
        // Trong bố cục gốc các màu nằm ngược chiều kim đồng hồ theo thứ tự, Xanh dương (thứ 1) ở góc dưới trái.
        turns = ((1 - index) % 4 + 4) % 4
    }

    func point(_ point: CGPoint) -> CGPoint {
        let size = CGFloat(BoardLayout.gridSize)
        var result = point
        for _ in 0..<turns { result = CGPoint(x: result.y, y: size - result.x) }
        return result
    }

    func cell(_ cell: GridCell) -> GridCell {
        var result = cell
        for _ in 0..<turns { result = GridCell(column: result.row, row: BoardLayout.gridSize - 1 - result.column) }
        return result
    }

    var track: [GridCell] { BoardLayout.track.map(cell) }
    var center: GridCell { BoardLayout.center }

    func homeCell(rung: Int, color: PlayerColor) -> GridCell { cell(BoardLayout.homeCell(rung: rung, color: color)) }

    /// Tâm của chuồng 6×6 ô.
    func stableCenter(of color: PlayerColor) -> CGPoint {
        let origin = BoardLayout.stableOrigin(of: color)
        return point(CGPoint(x: CGFloat(origin.column) + 3, y: CGFloat(origin.row) + 3))
    }

    func stableSlot(of color: PlayerColor, index: Int) -> CGPoint { point(BoardLayout.stableSlot(of: color, index: index)) }

    func gridPoint(for position: HorsePosition, horse: HorseID) -> CGPoint { point(BoardLayout.gridPoint(for: position, horse: horse)) }
}
