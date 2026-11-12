public enum MoveKind: String, Codable, Sendable {
    /// Ra quân: từ chuồng xuống ô xuất phát.
    case release
    /// Đi trên đường chạy.
    case advance
    /// Lên hoặc leo trong cột về đích.
    case climb
    /// Bay tới ô cửa chuồng kế tiếp phía trước (dùng một viên xúc xắc ra 1).
    case fly
}

/// Cách một nước đi dùng các viên xúc xắc còn lại của lượt.
public enum DiceUse: Codable, Hashable, Sendable {
    /// Đi số bước của viên thứ `index` trong các viên còn lại. Chế độ một xúc xắc luôn là `die(index: 0)`.
    case die(index: Int)
    /// Cộng hai viên còn lại cho một quân (chỉ ở chế độ hai xúc xắc).
    case sum
    /// Dùng một viên ra 1 để bay.
    case fly
}

/// Một nước đi hợp lệ đã được tính sẵn đầy đủ hệ quả.
public struct Move: Codable, Equatable, Sendable {
    public let horse: HorseID
    /// Số bước của nước đi: giá trị một viên, hoặc tổng hai viên. Với nước bay là 1 (viên được dùng).
    public let roll: Int
    public let kind: MoveKind
    public let from: HorsePosition
    public let to: HorsePosition
    /// Các vị trí lần lượt đi qua sau `from`, kết thúc ở `to` (dùng cho hoạt ảnh). Nước bay chỉ có điểm đáp.
    public let path: [HorsePosition]
    /// Các quân đối phương bị đá về chuồng.
    public let captures: [HorseID]
    public let use: DiceUse

    /// Hành động tương ứng để gửi vào `GameEngine`.
    public var action: GameAction { .move(horse: horse, use: use) }
}

/// Nơi duy nhất quyết định một nước đi có hợp lệ hay không.
public enum MoveValidator {
    /// Mọi nước hợp lệ của `color` với các viên xúc xắc còn lại `dice` (một hoặc hai viên).
    public static func legalMoves(in state: GameState, for color: PlayerColor, dice: [Int]) -> [Move] {
        guard let player = state.player(color), player.status == .active else { return [] }
        return player.horses.indices.flatMap { options(in: state, horse: HorseID(color, $0), dice: dice) }
    }

    /// Mọi nước hợp lệ với một viên xúc xắc ra `roll` (gồm cả nước bay nếu `roll` là 1).
    public static func legalMoves(in state: GameState, for color: PlayerColor, roll: Int) -> [Move] {
        legalMoves(in: state, for: color, dice: [roll])
    }

    /// Các nước một quân có thể đi với các viên còn lại: đi theo từng viên, cộng hai viên, hoặc bay.
    public static func options(in state: GameState, horse: HorseID, dice: [Int]) -> [Move] {
        var result: [Move] = []
        var seen = Set<Int>()
        // Hai viên giống nhau cho cùng một nước, chỉ liệt kê một lần.
        for (index, value) in dice.enumerated() where seen.insert(value).inserted {
            if let move = resolve(.die(index: index), in: state, horse: horse, dice: dice) { result.append(move) }
        }
        for use in [DiceUse.sum, .fly] {
            if let move = resolve(use, in: state, horse: horse, dice: dice) { result.append(move) }
        }
        return result
    }

    /// Nước đi ứng với một cách dùng xúc xắc cụ thể, hoặc `nil` nếu không hợp lệ.
    public static func resolve(_ use: DiceUse, in state: GameState, horse: HorseID, dice: [Int]) -> Move? {
        guard dice.allSatisfy(GameRules.diceRange.contains), (1...GameRules.maxDice).contains(dice.count) else { return nil }
        switch use {
        case .die(let index):
            guard dice.indices.contains(index) else { return nil }
            return step(in: state, horse: horse, steps: dice[index], use: use, allowRelease: true)
        case .sum:
            // Cộng điểm không dùng để ra quân: ra quân cần đúng một viên ra giá trị cho phép.
            guard dice.count == 2,
                  let move = step(in: state, horse: horse, steps: dice[0] + dice[1], use: use, allowRelease: false) else { return nil }
            // Lên và leo cột đích phải đổ đúng số của bậc bằng MỘT viên; tổng hai viên không được tính.
            // (Kiểu Ludo `pipCount` đi theo số chấm nên vẫn cộng được.)
            if state.rules.homeEntry != .pipCount, move.to.isHome { return nil }
            return move
        case .fly:
            guard state.rules.flyOnOne, dice.contains(1) else { return nil }
            return flight(in: state, horse: horse)
        }
    }

    /// Nước đi thường của `horse` với một viên ra `roll` (không tính nước bay), hoặc `nil` nếu không đi được.
    public static func move(in state: GameState, horse: HorseID, roll: Int) -> Move? {
        guard GameRules.diceRange.contains(roll) else { return nil }
        return step(in: state, horse: horse, steps: roll, use: .die(index: 0), allowRelease: true)
    }

    private static func step(in state: GameState, horse: HorseID, steps: Int, use: DiceUse, allowRelease: Bool) -> Move? {
        guard steps >= 1,
              let from = state.position(of: horse),
              state.player(horse.color)?.status == .active,
              allowRelease || !from.isStable,
              let path = route(from: from, color: horse.color, roll: steps, rules: state.rules),
              let to = path.last else { return nil }

        if state.rules.blocking {
            for position in path.dropLast() where isOccupied(position, color: horse.color, in: state) { return nil }
        }
        guard let captures = landing(on: to, horse: horse, in: state) else { return nil }
        let kind: MoveKind = from.isStable ? .release : (to.isHome ? .climb : .advance)
        return Move(horse: horse, roll: steps, kind: kind, from: from, to: to, path: path, captures: captures, use: use)
    }

    /// Bay: quân trên đường chạy nhảy tới ô cửa chuồng gần nhất phía trước (của bất kỳ màu nào). Bay cũng bị cản đường:
    /// mọi ô giữa quân và ô đáp phải trống. Ô xa nhất phía trước luôn là cửa chuồng của chính mình, nên không bao giờ bay quá.
    private static func flight(in state: GameState, horse: HorseID) -> Move? {
        guard let from = state.position(of: horse), let square = from.trackSquare,
              state.player(horse.color)?.status == .active,
              let progress = Board.progress(ofSquare: square, for: horse.color),
              progress < Board.stepsToMouth else { return nil }
        // Tính theo quãng đường của chính quân đó, các ô cửa chuồng nằm ở bước 13, 26, 39 và 52.
        let landingProgress = (progress / Board.stepsPerSide + 1) * Board.stepsPerSide
        if state.rules.blocking {
            for between in (progress + 1)..<landingProgress
            where !state.horses(onTrack: Board.square(atProgress: between, for: horse.color)).isEmpty { return nil }
        }
        let to = HorsePosition.track(Board.square(atProgress: landingProgress, for: horse.color))
        guard let captures = landing(on: to, horse: horse, in: state) else { return nil }
        return Move(horse: horse, roll: 1, kind: .fly, from: from, to: to, path: [to], captures: captures, use: .fly)
    }

    /// Kiểm tra ô đáp. Trả về danh sách quân bị đá, hoặc `nil` nếu không được đáp xuống đó.
    private static func landing(on position: HorsePosition, horse: HorseID, in state: GameState) -> [HorseID]? {
        let rules = state.rules
        switch position {
        case .stable:
            return nil
        case .home(let rung):
            return state.isRungOccupied(rung, color: horse.color) ? nil : []
        case .track(let square):
            let occupants = state.horses(onTrack: square)
            let own = occupants.filter { $0.color == horse.color }
            let others = occupants.filter { $0.color != horse.color }
            if !own.isEmpty && !rules.allowStacking { return nil }
            guard !others.isEmpty, !Board.safeSquares(for: rules.safeSquares).contains(square) else { return [] }
            // Khi cho chồng quân, một ô có từ hai quân cùng màu là "hàng rào", không đá được.
            let stacks = Dictionary(grouping: others, by: \.color)
            if rules.allowStacking && stacks.values.contains(where: { $0.count >= 2 }) { return nil }
            return others
        }
    }

    /// Đường đi thuần hình học (chưa xét quân cản), hoặc `nil` nếu số bước không dùng được.
    static func route(from: HorsePosition, color: PlayerColor, roll: Int, rules: RulesConfiguration) -> [HorsePosition]? {
        switch from {
        case .stable:
            return rules.releaseValues.contains(roll) ? [.track(Board.startSquare(of: color))] : nil

        case .track(let square):
            guard let progress = Board.progress(ofSquare: square, for: color) else { return nil }
            switch rules.homeEntry {
            case .exactRungDirect, .exactRungStepwise:
                if progress == Board.stepsToMouth {
                    if rules.homeEntry == .exactRungStepwise { return roll == 1 ? [.home(1)] : nil }
                    guard roll <= Board.homeRungs else { return nil }
                    return (1...roll).map { .home($0) }
                }
                // Phải dừng đúng ô cửa chuồng, không được đi quá.
                guard progress + roll <= Board.stepsToMouth else { return nil }
                return (1...roll).map { .track(Board.square(atProgress: progress + $0, for: color)) }
            case .pipCount:
                guard progress + roll <= Board.stepsToMouth + Board.homeRungs else { return nil }
                return (1...roll).map { step in
                    let target = progress + step
                    return target <= Board.stepsToMouth
                        ? .track(Board.square(atProgress: target, for: color))
                        : .home(target - Board.stepsToMouth)
                }
            }

        case .home(let rung):
            switch rules.homeEntry {
            case .exactRungDirect, .exactRungStepwise:
                return rung < Board.homeRungs && roll == rung + 1 ? [.home(rung + 1)] : nil
            case .pipCount:
                guard rung + roll <= Board.homeRungs else { return nil }
                return (1...roll).map { .home(rung + $0) }
            }
        }
    }

    private static func isOccupied(_ position: HorsePosition, color: PlayerColor, in state: GameState) -> Bool {
        switch position {
        case .stable: return false
        case .track(let square): return !state.horses(onTrack: square).isEmpty
        case .home(let rung): return state.isRungOccupied(rung, color: color)
        }
    }
}
