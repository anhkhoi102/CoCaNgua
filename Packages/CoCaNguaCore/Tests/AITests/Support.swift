import GameCore

/// Dựng nhanh một trạng thái ván với vị trí quân tuỳ ý.
func makeState(_ colors: [PlayerColor] = [.red, .green],
               rules: RulesConfiguration = .traditional,
               horses: [PlayerColor: [HorsePosition]] = [:],
               current: PlayerColor? = nil) -> GameState {
    var state = GameState(colors: colors, rules: rules)
    for (color, positions) in horses {
        let index = state.playerIndex(of: color)!
        state.players[index].horses = positions + Array(repeating: .stable, count: Board.horsesPerPlayer - positions.count)
    }
    if let current { state.currentPlayerIndex = state.playerIndex(of: current)! }
    return state
}

/// Ô trên đường chạy ứng với số bước `progress` của màu `color`.
func sq(_ progress: Int, _ color: PlayerColor) -> HorsePosition {
    .track(Board.square(atProgress: progress, for: color))
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
