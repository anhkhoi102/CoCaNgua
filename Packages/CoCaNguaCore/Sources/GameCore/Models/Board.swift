/// Hình học bàn Cờ Cá Ngựa: vòng 56 ô (14 ô mỗi màu), đi một chiều quanh bàn (chiều hiển thị do tầng vẽ quyết định).
///
/// Trong 56 ô có bốn **ô xuất phát** (ô chờ), mỗi màu một ô. Ô xuất phát nằm ngoài đường chạy: chỉ quân vừa ra của
/// đúng màu đó được đứng, quân màu khác đi vòng qua thì nhảy qua mà không tính bước. Vì vậy quãng đường của một quân
/// gồm ô xuất phát của nó (bước 0) rồi 52 ô chung, kết thúc ở ô cửa chuồng (bước 52), sau đó là cột về đích 6 bậc.
public enum Board {
    public static let squaresPerSide = 14
    public static let trackLength = squaresPerSide * PlayerColor.allCases.count
    public static let homeRungs = 6
    public static let horsesPerPlayer = 4
    /// Số bước giữa hai ô cửa chuồng liên tiếp trên quãng đường của một quân (14 ô mỗi cạnh trừ ô xuất phát).
    public static let stepsPerSide = squaresPerSide - 1
    /// Số bước từ ô xuất phát tới ô cửa chuồng của mình (đi trọn một vòng, không đếm ô xuất phát của màu khác).
    public static let stepsToMouth = stepsPerSide * PlayerColor.allCases.count

    /// Ô quân đặt chân khi ra quân.
    public static func startSquare(of color: PlayerColor) -> Int {
        color.rawValue * squaresPerSide
    }

    /// Ô này có phải ô xuất phát của một màu nào đó không.
    public static func isStartSquare(_ square: Int) -> Bool {
        square % squaresPerSide == 0
    }

    /// Ô "cửa chuồng": ô cuối vòng, ngay trước ô xuất phát, nơi quân bắt đầu leo cột về đích.
    public static func mouthSquare(of color: PlayerColor) -> Int {
        square(atProgress: stepsToMouth, for: color)
    }

    /// Số bước quân màu `color` đã đi kể từ ô xuất phát của mình (0...stepsToMouth), hoặc `nil` nếu `square` là ô
    /// xuất phát của màu khác (không nằm trên quãng đường của màu này).
    public static func progress(ofSquare square: Int, for color: PlayerColor) -> Int? {
        let offset = (square - startSquare(of: color) + trackLength) % trackLength
        guard offset == 0 || !isStartSquare(square) else { return nil }
        // Trừ đi số ô xuất phát của màu khác đã nhảy qua.
        return offset - offset / squaresPerSide
    }

    public static func square(atProgress progress: Int, for color: PlayerColor) -> Int {
        let skipped = progress > 0 ? (progress - 1) / stepsPerSide : 0
        return (startSquare(of: color) + progress + skipped) % trackLength
    }

    /// Các ô an toàn theo cấu hình luật. Luật truyền thống không có ô an toàn.
    public static func safeSquares(for rule: SafeSquareRule) -> Set<Int> {
        let starts = PlayerColor.allCases.map(startSquare(of:))
        switch rule {
        case .none:
            return []
        case .startSquares:
            // Ô xuất phát vốn chỉ quân chủ nhà đứng được nên không cần đánh dấu an toàn.
            return []
        case .startAndMidSquares:
            return Set(starts.map { ($0 + squaresPerSide / 2) % trackLength })
        }
    }
}
