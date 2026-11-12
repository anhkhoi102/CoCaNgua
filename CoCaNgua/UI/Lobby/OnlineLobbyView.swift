import GameCore
import OnlineCore
import SwiftUI

/// Phòng chờ chơi mạng: trạng thái Game Center, tạo trận riêng, tìm trận công khai, và các trận đang dở.
struct OnlineLobbyView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var playerCount = 2
    @State private var joinCode = ""
    /// Bản Debug: hiện các thẻ của người đã đăng nhập để soát giao diện khi chưa có Game Center (COCANGUA_LOBBY_PREVIEW).
    private static let previewsSignedIn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCANGUA_LOBBY_PREVIEW"] != nil
        #else
        return false
        #endif
    }()

    var body: some View {
        let gameCenter = coordinator.gameCenter
        let online = coordinator.online
        let rooms = coordinator.rooms
        VStack(spacing: Device.isPhone ? 8 : 16) {
            Text(L("Chơi mạng", "Online"))
                .font(.screenTitle)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 4)

            ScrollView {
                VStack(spacing: 14) {
                    LobbyCard(title: "Game Center") { statusRow(gameCenter.status) }

                    if gameCenter.isSignedIn || Self.previewsSignedIn {
                        if rooms.isActive || Self.previewsSignedIn {
                            roomCard(rooms)
                        }
                        if !rooms.isActive {
                            LobbyCard(title: L("Tạo phòng", "Create a room")) {
                                Picker(L("Số chỗ", "Seats"), selection: $playerCount) {
                                    ForEach(GameRules.minPlayers...GameRules.maxPlayers, id: \.self) { Text(L("\($0) người", "\($0) players")).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                Button(L("Tạo phòng và lấy mã", "Create room & get a code")) {
                                    coordinator.click()
                                    rooms.createRoom(seatCount: playerCount)
                                }
                                .buttonStyle(ChunkyButtonStyle(tint: .player(.green)))
                                Text(L("Bạn nhận một mã 6 số để gửi cho bạn bè, thấy ai đã vào phòng và bấm Bắt đầu khi muốn. Chỗ còn trống sẽ do máy chơi. Mọi người cần mở app trong suốt ván.", "You get a 6-digit code to send to friends, see who has joined, and press Start whenever you like. Empty seats are played by bots. Everyone needs to keep the app open during the game."))
                                    .font(.baloo(13, .regular))
                                    .foregroundStyle(Color.ink.opacity(0.6))
                            }

                            LobbyCard(title: L("Vào phòng bằng mã", "Join with a code")) {
                                HStack(spacing: 12) {
                                    TextField(L("Mã phòng 6 số", "6-digit room code"), text: $joinCode)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.baloo(20, .bold))
                                        .monospacedDigit()
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .frame(maxWidth: 220)
                                        .onChange(of: joinCode) { joinCode = String(joinCode.filter(\.isNumber).prefix(RoomCode.length)) }
                                    Button(L("Vào phòng", "Join room")) {
                                        coordinator.click()
                                        if rooms.joinRoom(code: joinCode) { joinCode = "" }
                                    }
                                    .buttonStyle(ChunkyButtonStyle(tint: .player(.blue)))
                                    .disabled(RoomCode(joinCode) == nil)
                                }
                            }

                            LobbyCard(title: L("Trận theo lượt", "Turn-based matches")) {
                                Text(L("Kiểu chơi không cần cùng online: mỗi người đi khi rảnh, Game Center báo khi tới lượt.", "Play without being online together: everyone moves when free, and Game Center notifies you when it is your turn."))
                                    .font(.baloo(13, .regular))
                                    .foregroundStyle(Color.ink.opacity(0.6))
                                HStack(spacing: 14) {
                                    Button(L("Mời qua danh sách bạn bè", "Invite from friends list")) { online.invitePlayers(playerCount: playerCount) }
                                    Button(L("Ghép với người lạ", "Match with strangers")) { Task { await online.findPublicMatch(playerCount: playerCount) } }
                                    Button(L("Làm mới", "Refresh")) { Task { await online.refresh() } }
                                }
                                .linkButtonStyle()
                                .font(.baloo(14, .semibold))
                                .disabled(online.isBusy)
                                if online.isBusy {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text(L("Đang kết nối với Game Center…", "Connecting to Game Center…"))
                                    }
                                }
                                ForEach(online.matches) { match in
                                    MatchRow(match: match,
                                             open: { Task { await online.open(matchID: match.id) } },
                                             remove: { Task { await online.remove(matchID: match.id) } })
                                }
                            }
                        }
                    }

                    if let message = rooms.errorMessage ?? online.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.baloo(14, .medium))
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.player(.red)))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: Device.isPhone ? 760 : 600)

            Button(L("Quay lại", "Back")) {
                coordinator.click()
                coordinator.showMainMenu()
            }
            .buttonStyle(ChunkyButtonStyle(prominent: false))
            .frame(width: 220)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.vertical, Device.isPhone ? 10 : 28)
        .padding(.horizontal, 40)
    }

    /// Sảnh chờ của phòng: mã, những ai đã vào, và nút Bắt đầu cho chủ phòng.
    private func roomCard(_ rooms: RoomManager) -> some View {
        LobbyCard(title: rooms.isHost ? L("Phòng của bạn", "Your room") : L("Phòng", "Room")) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L("Mã phòng", "Room code")).font(.baloo(15, .semibold)).opacity(0.7)
                Text(rooms.roomCode ?? "------").font(.baloo(34, .heavy)).monospacedDigit().tracking(4).textSelection(.enabled)
                Spacer()
                Text(L("\(rooms.members.count)/\(rooms.seatCount) người", "\(rooms.members.count)/\(rooms.seatCount) players"))
                    .font(.baloo(16, .bold))
            }
            VStack(spacing: 6) {
                ForEach(rooms.members) { member in
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                        Text(member.name).font(.baloo(16, .semibold)).lineLimit(1)
                        if member.isHost {
                            Text(L("Chủ phòng", "Host")).font(.baloo(12, .bold)).padding(.horizontal, 7).padding(.vertical, 1)
                                .background(Capsule().fill(Color.player(.yellow).opacity(0.35)))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.player(.green).opacity(0.14)))
                }
                ForEach(0..<max(0, rooms.seatCount - rooms.members.count), id: \.self) { _ in
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                        Text(L("Chỗ trống — máy sẽ chơi nếu không ai vào", "Empty seat — a bot plays if nobody joins")).font(.baloo(14, .medium))
                        Spacer()
                    }
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
            }
            HStack(spacing: 8) {
                if rooms.phase == .searching || !rooms.canStart { ProgressView().controlSize(.small) }
                Text(roomHint(rooms)).font(.baloo(13, .regular)).foregroundStyle(Color.ink.opacity(0.65))
            }
            HStack(spacing: 12) {
                Button(L("Rời phòng", "Leave room")) {
                    coordinator.click()
                    rooms.leave()
                }
                .buttonStyle(ChunkyButtonStyle(prominent: false))
                if rooms.isHost {
                    Button(L("Bắt đầu", "Start")) {
                        coordinator.click()
                        rooms.start()
                    }
                    .buttonStyle(ChunkyButtonStyle(tint: .player(.green)))
                    .disabled(!rooms.canStart)
                }
            }
        }
    }

    private func roomHint(_ rooms: RoomManager) -> String {
        if rooms.isHost {
            return rooms.canStart
                ? L("Bấm Bắt đầu khi đã đủ người bạn muốn. Chỗ trống sẽ do máy chơi.", "Press Start when everyone you want is here. Empty seats are played by bots.")
                : L("Gửi mã này cho bạn bè. Cần ít nhất một người vào thì mới bắt đầu được.", "Send this code to your friends. At least one person must join before you can start.")
        }
        return rooms.phase == .searching
            ? L("Đang tìm phòng… Chủ phòng cần đang mở phòng với đúng mã này.", "Looking for the room… The host must have the room open with this exact code.")
            : L("Đã vào phòng. Đang chờ chủ phòng bắt đầu…", "You are in. Waiting for the host to start…")
    }

    @ViewBuilder
    private func statusRow(_ status: GameCenterManager.Status) -> some View {
        switch status {
        case .signedOut, .signingIn:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Đang đăng nhập…", "Signing in…"))
            }
        case .signedIn(let name):
            Label(L("Đã đăng nhập: \(name)", "Signed in: \(name)"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.player(.green))
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Chưa dùng được Game Center", "Game Center is unavailable"), systemImage: "xmark.circle.fill")
                    .foregroundStyle(Color.player(.red))
                Text(reason).font(.baloo(14, .regular)).foregroundStyle(Color.ink.opacity(0.7))
                Text(L("Nguyên nhân thường gặp: chưa đăng nhập Game Center trong Cài đặt hệ thống, hoặc bản ứng dụng này chưa được ký với quyền Game Center (cần tài khoản Apple Developer).", "Common causes: you are not signed in to Game Center in System Settings, or this build is not signed with the Game Center entitlement (needs an Apple Developer account)."))
                    .font(.baloo(13, .regular)).foregroundStyle(Color.ink.opacity(0.55))
                Button(L("Thử lại", "Try again")) { coordinator.gameCenter.signIn() }
                    .linkButtonStyle()
            }
        }
    }
}

private struct MatchRow: View {
    var match: OnlineMatchSummary
    var open: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(match.isMyTurn ? Color.player(.green) : Color.ink.opacity(0.2)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(match.opponents).font(.baloo(16, .semibold)).lineLimit(1)
                    if let code = match.roomCode {
                        Text(L("Mã \(code)", "Code \(code)")).font(.baloo(12, .bold)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .background(Capsule().fill(Color.ink.opacity(0.1)))
                    }
                }
                Text(match.status).font(.baloo(13, .regular)).foregroundStyle(Color.ink.opacity(0.65))
            }
            Spacer()
            if match.isFinished {
                Button(L("Xoá", "Remove"), action: remove).linkButtonStyle()
            }
            Button(match.isFinished ? L("Xem", "View") : L("Vào", "Open"), action: open)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

private struct LobbyCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.baloo(20, .bold))
            content
        }
        .font(.baloo(16, .medium))
        .foregroundStyle(Color.ink)
        .tint(.player(.green))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.panel)
            .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 4))
        .environment(\.colorScheme, .light)
    }
}
