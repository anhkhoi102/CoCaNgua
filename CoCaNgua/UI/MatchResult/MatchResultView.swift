import GameCore
import SwiftUI

struct MatchResultView: View {
    @Environment(AppCoordinator.self) private var coordinator
    var result: MatchResult
    var session: GameSession

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: Device.isPhone ? 9 : 16) {
                HorseToken(color: result.winner, size: Device.isPhone ? 54 : 84)
                Text(headline)
                    .font(.baloo(Device.isPhone ? 30 : 40, .heavy))
                    .foregroundStyle(Color.player(result.winner))
                VStack(spacing: 6) {
                    ForEach(Array(result.standings.enumerated()), id: \.offset) { rank, color in
                        HStack(spacing: 10) {
                            Text("\(rank + 1)").font(.baloo(18, .heavy)).frame(width: 24)
                            HorseToken(color: color, size: 28)
                            Text(session.seat(color).name).font(.baloo(17, .semibold))
                            Spacer()
                            Text(L("\(session.state.player(color)?.horsesHome ?? 0)/\(Board.horsesPerPlayer) về đích", "\(session.state.player(color)?.horsesHome ?? 0)/\(Board.horsesPerPlayer) home"))
                                .font(.baloo(14, .medium)).opacity(0.7)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.player(color).opacity(rank == 0 ? 0.22 : 0.08)))
                    }
                }
                HStack(spacing: 18) {
                    Label(durationText, systemImage: "clock")
                    Label(L("\(result.turns) lượt", "\(result.turns) turns"), systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.baloo(15, .medium))
                .opacity(0.75)
                HStack(spacing: 12) {
                    Button(session.isOnline ? L("Về phòng chờ", "Back to lobby") : L("Về menu", "Back to menu")) {
                        coordinator.click()
                        if session.isOnline { coordinator.leaveOnlineMatch(resign: false) } else { coordinator.showMainMenu() }
                    }
                    .buttonStyle(ChunkyButtonStyle(prominent: false))
                    if !session.isLive {
                    Button(session.isOnline ? L("Đấu lại", "Rematch") : L("Chơi lại", "Play again")) {
                        coordinator.click()
                        if session.isOnline { Task { await coordinator.online.rematch() } } else { coordinator.startSinglePlayer() }
                    }
                    .buttonStyle(ChunkyButtonStyle(tint: .player(.green)))
                    .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 4)
            }
            .foregroundStyle(Color.ink)
            .padding(Device.isPhone ? 18 : 26)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.panel)
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.player(result.winner), lineWidth: 4))
        }
    }

    private var headline: String {
        session.seat(result.winner).controller == .human
            ? L("Bạn thắng!", "You win!")
            : L("\(session.seat(result.winner).name) thắng", "\(session.seat(result.winner).name) wins")
    }

    private var durationText: String {
        let total = Int(result.duration.rounded())
        return L("\(total / 60) phút \(total % 60) giây", "\(total / 60) min \(total % 60) s")
    }
}
