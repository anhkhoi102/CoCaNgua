import GameCore
import SwiftUI

/// Thiết lập ván chơi đơn: màu quân của người chơi, số đối thủ máy và độ khó.
struct SinglePlayerSetupView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = coordinator.settings
        VStack(spacing: 12) {
            Text(L("Chơi đơn", "Single player"))
                .font(.screenTitle)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 4)

            PhoneScroll {
              VStack(spacing: 10) {
                SetupCard(title: L("Màu quân của bạn", "Your colour")) {
                    HStack(spacing: 14) {
                        ForEach(PlayerColor.allCases, id: \.self) { color in
                            ColorChoice(color: color, isSelected: settings.lastHumanColor == color) {
                                coordinator.click()
                                settings.lastHumanColor = color
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                SetupCard(title: L("Số đối thủ máy", "Computer opponents")) {
                    Picker(L("Số đối thủ máy", "Computer opponents"), selection: $settings.lastOpponentCount) {
                        ForEach(1...3, id: \.self) { Text(L("\($0) máy", "\($0) bot\($0 == 1 ? "" : "s")")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack(spacing: 8) {
                        ForEach(preview.seats) { seat in
                            HStack(spacing: 5) {
                                HorseToken(color: seat.color, size: 26)
                                Text(seat.name).font(.baloo(14, .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.player(seat.color).opacity(0.16)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                SetupCard(title: L("Độ khó", "Difficulty")) {
                    Picker(L("Độ khó", "Difficulty"), selection: $settings.lastDifficulty) {
                        ForEach(AIDifficulty.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.lastDifficulty.summary)
                        .font(.baloo(14, .regular))
                        .foregroundStyle(Color.ink.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("Độ khó chỉ thay đổi cách máy chọn nước đi. Xúc xắc luôn ngẫu nhiên như nhau cho mọi người.", "Difficulty only changes how the computer picks its moves. The dice are equally random for everyone."))
                        .font(.baloo(12, .regular))
                        .foregroundStyle(Color.ink.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SetupCard(title: L("Chế độ", "Mode")) {
                    Toggle(L("Chế độ nhanh: đổ 2 xúc xắc mỗi lượt", "Speed mode: roll 2 dice each turn"), isOn: Binding(
                        get: { settings.rules.diceCount == 2 },
                        set: { settings.rules.diceCount = $0 ? 2 : 1 }))
                    Text(L("Mỗi viên đi một nước, hoặc cộng hai viên cho một quân. Ra đôi được đổ thêm. Ở cả hai chế độ, viên ra 1 cho phép bay tới cửa chuồng kế tiếp.", "Each die makes a move, or add both for one piece. Doubles roll again. A 1 can fly a piece to the next gate."))
                        .font(.baloo(12, .regular))
                        .foregroundStyle(Color.ink.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .padding(.horizontal, 4)
            }
            .frame(maxWidth: Device.isPhone ? 760 : 568)

            HStack(spacing: 14) {
                Button(L("Quay lại", "Back")) {
                    coordinator.click()
                    coordinator.showMainMenu()
                }
                .buttonStyle(ChunkyButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)
                Button(L("Bắt đầu", "Start")) {
                    coordinator.click()
                    coordinator.startSinglePlayer()
                }
                .buttonStyle(ChunkyButtonStyle(tint: .player(settings.lastHumanColor)))
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 420)
        }
        .padding(.vertical, Device.isPhone ? 10 : 16)
        .padding(.horizontal, 40)
    }

    /// Chỗ ngồi sẽ có trong ván, để người chơi thấy trước mình đấu với những màu nào.
    private var preview: MatchConfiguration {
        MatchConfiguration.singlePlayer(humanColor: coordinator.settings.lastHumanColor, opponents: coordinator.settings.lastOpponentCount,
                                        difficulty: coordinator.settings.lastDifficulty, rules: coordinator.settings.rules)
    }
}

private struct ColorChoice: View {
    var color: PlayerColor
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HorseToken(color: color, size: 52)
                Text(Theme.name(color)).font(.baloo(14, .semibold)).foregroundStyle(Color.ink)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.player(color).opacity(isSelected ? 0.22 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.player(color), lineWidth: isSelected ? 3.5 : 0))
            .scaleEffect(isSelected ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Theme.name(color)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetupCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.baloo(18, .bold))
            content
        }
        .font(.baloo(15, .medium))
        .foregroundStyle(Color.ink)
        .tint(.player(.green))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.panel)
            .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 4))
        .environment(\.colorScheme, .light)
    }
}
