import GameCore
import SpriteKit
import SwiftUI

struct GameView: View {
    @Environment(AppCoordinator.self) private var coordinator
    var session: GameSession
    @State private var confirmingExit = false

    var body: some View {
        Group {
            if Device.isPhone {
                // iPhone nằm ngang: bàn cờ chiếm phần lớn màn hình, xúc xắc bên phải, người chơi thu nhỏ thành một hàng ở mép dưới.
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        board.padding(.horizontal, 6).padding(.top, 4)
                        VStack(spacing: 10) {
                            header
                            dicePanel
                            connectionNote
                            exitButton
                        }
                        .frame(width: 236)
                        .padding(.trailing, 12)
                    }
                    HStack(spacing: 8) {
                        ForEach(session.configuration.seats) { seat in
                            PlayerChip(seat: seat, player: session.state.player(seat.color),
                                       isActive: session.result == nil && session.diceOwner == seat.color)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            } else {
                HStack(spacing: 0) {
                    board.padding(8)
                    sidePanel
                        .frame(width: 300)
                        .padding(.vertical, 14)
                        .padding(.trailing, 18)
                }
            }
        }
        .overlay {
            if let result = session.result {
                MatchResultView(result: result, session: session)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: session.result)
        .confirmationDialog(L("Rời ván đang chơi?", "Leave this game?"), isPresented: $confirmingExit) {
            if session.isLive {
                Button(L("Rời phòng", "Leave room"), role: .destructive) { coordinator.leaveOnlineMatch(resign: true) }
            } else if session.isOnline {
                Button(L("Tạm rời (ván vẫn tiếp tục)", "Step away (the match continues)")) { coordinator.leaveOnlineMatch(resign: false) }
                Button(L("Bỏ cuộc", "Resign"), role: .destructive) { coordinator.leaveOnlineMatch(resign: true) }
            } else {
                Button(L("Về menu", "Back to menu"), role: .destructive) { coordinator.showMainMenu() }
            }
            Button(L("Chơi tiếp", "Keep playing"), role: .cancel) {}
        } message: {
            Text(session.isLive ? L("Bạn sẽ không vào lại được ván này. Máy sẽ chơi thay bạn; nếu bạn là chủ phòng thì ván kết thúc với mọi người.", "You will not be able to rejoin this game. A bot takes over your pieces; if you are the host, the game ends for everyone.")
                 : session.isOnline ? L("Tạm rời thì bạn vào lại được từ phòng chờ. Bỏ cuộc thì quân của bạn bị gỡ khỏi bàn.", "If you step away you can rejoin from the lobby. If you resign, your pieces are removed from the board.")
                                  : L("Ván này sẽ không được lưu.", "This game will not be saved."))
        }
    }

    private var board: some View {
        SpriteView(scene: session.scene, options: [.allowsTransparency])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidePanel: some View {
        VStack(spacing: 10) {
            header
            playerCards
            Spacer(minLength: 0)
            dicePanel
            Spacer(minLength: 0)
            connectionNote
            exitButton
        }
    }

    private var header: some View {
            HStack {
                Text("Cờ Cá Ngựa").font(.baloo(24, .heavy))
                if session.isOnline {
                    Text(L("Chơi mạng", "Online")).font(.baloo(12, .bold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                Spacer()
                Text(L("Lượt \(session.state.turnNumber)", "Turn \(session.state.turnNumber)")).font(.baloo(15, .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
    }

    private var playerCards: some View {
            VStack(spacing: 6) {
                ForEach(session.configuration.seats) { seat in
                    PlayerCard(seat: seat, player: session.state.player(seat.color),
                               isActive: session.result == nil && session.diceOwner == seat.color)
                }
            }
    }

    @ViewBuilder private var connectionNote: some View {
            if let code = session.roomCode, session.result == nil {
                VStack(spacing: 0) {
                    Text(L("Mã phòng", "Room code")).font(.baloo(12, .semibold)).opacity(0.7)
                    Text(code).font(.baloo(24, .heavy)).monospacedDigit().tracking(3).textSelection(.enabled)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.panel))
            }
            if let note = session.connectionNote {
                Label(note, systemImage: "wifi.exclamationmark")
                    .font(.baloo(13, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.player(.red)))
            }
    }

    private var exitButton: some View {
            Button(session.isOnline ? L("Rời ván", "Leave") : L("Về menu", "Back to menu")) {
                coordinator.click()
                if session.result == nil {
                    confirmingExit = true
                } else if session.isOnline {
                    coordinator.leaveOnlineMatch(resign: false)
                } else {
                    coordinator.showMainMenu()
                }
            }
            .buttonStyle(ChunkyButtonStyle(prominent: false))
    }

    private var dicePanel: some View {
        let owner = session.seat(session.diceOwner)
        return VStack(spacing: 8) {
            Text(owner.controller == .human ? L("Lượt của bạn", "Your turn") : L("Lượt của \(owner.name)", "\(owner.name)'s turn"))
                .font(.baloo(17, .bold))
                .foregroundStyle(Color.player(owner.color))
            HStack(spacing: 14) {
                ForEach(Array(session.diceFaces.enumerated()), id: \.offset) { index, face in
                    DiceView(face: face, tilt: index == 0 ? session.diceTilt : -session.diceTilt, rolling: session.diceRolling,
                             tint: .player(owner.color), size: session.diceFaces.count > 1 ? 66 : 78)
                        .opacity(session.diceUsed.indices.contains(index) && session.diceUsed[index] ? 0.3 : 1)
                }
            }
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.2), value: session.diceUsed)
            Text(session.message)
                .font(.baloo(15, .medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Đổ xúc xắc", "Roll dice")) { session.humanRoll() }
                .buttonStyle(ChunkyButtonStyle(tint: .player(session.humanColor ?? owner.color)))
                .disabled(!session.awaitingHumanRoll)
                .keyboardShortcut(.space, modifiers: [])
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.panel)
            .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 5))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.player(owner.color), lineWidth: 3))
        .animation(.easeInOut(duration: 0.2), value: session.diceOwner)
    }
}

/// Thẻ một người chơi: màu, tên, trạng thái từng quân và tiến độ.
private struct PlayerCard: View {
    var seat: Seat
    var player: Player?
    var isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            HorseToken(color: seat.color, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(seat.name).font(.baloo(17, .bold))
                    Text(roleLabel).font(.baloo(12, .medium)).opacity(0.6)
                }
                HStack(spacing: 5) {
                    ForEach(Array((player?.horses ?? []).enumerated()), id: \.offset) { _, position in
                        HorsePip(position: position, color: seat.color)
                    }
                    Spacer(minLength: 4)
                    Text(L("\(player?.horsesHome ?? 0)/\(Board.horsesPerPlayer) về đích", "\(player?.horsesHome ?? 0)/\(Board.horsesPerPlayer) home")).font(.baloo(12, .medium)).opacity(0.7)
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.panel)
            .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: isActive ? 5 : 3))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.player(seat.color), lineWidth: isActive ? 3.5 : 0))
        .scaleEffect(isActive ? 1.0 : 0.96)
        .opacity(player?.status == .resigned ? 0.5 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
    }

    private var roleLabel: String {
        if player?.status == .resigned { return L("Đã bỏ cuộc", "Resigned") }
        switch seat.controller {
        case .human: return Theme.name(seat.color)
        case .ai(let difficulty): return L("Máy · \(difficulty.title)", "Bot · \(difficulty.title)")
        case .remote: return L("Chơi mạng", "Online")
        }
    }
}

/// Thẻ người chơi thu gọn cho iPhone: một dòng gồm quân, tên, bốn chấm trạng thái; người đang tới lượt có viền màu.
private struct PlayerChip: View {
    var seat: Seat
    var player: Player?
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            HorseToken(color: seat.color, size: 24)
            Text(seat.name).font(.baloo(14, .bold)).lineLimit(1)
            HStack(spacing: 3) {
                ForEach(Array((player?.horses ?? []).enumerated()), id: \.offset) { _, position in
                    HorsePip(position: position, color: seat.color).scaleEffect(0.8).frame(width: 14, height: 14)
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: 230)
        .background(Capsule().fill(Color.panel).shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 2))
        .overlay(Capsule().strokeBorder(Color.player(seat.color), lineWidth: isActive ? 3 : 0))
        .opacity(player?.status == .resigned ? 0.5 : (isActive ? 1 : 0.85))
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

/// Chấm nhỏ cho một quân: rỗng = trong chuồng, đặc = trên đường chạy, có số = đã lên bậc đích.
private struct HorsePip: View {
    var position: HorsePosition
    var color: PlayerColor

    var body: some View {
        ZStack {
            switch position {
            case .stable:
                Circle().strokeBorder(Color.player(color), lineWidth: 2)
            case .track:
                Circle().fill(Color.player(color))
            case .home(let rung):
                Circle().fill(Color.player(color))
                Text("\(rung)").font(.baloo(11, .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 17, height: 17)
    }
}
