import GameCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = coordinator.settings
        VStack(spacing: Device.isPhone ? 8 : 18) {
            Text(L("Cài đặt", "Settings"))
                .font(.screenTitle)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 4)

            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(title: L("Ngôn ngữ", "Language")) {
                        Picker(L("Ngôn ngữ", "Language"), selection: $settings.language) {
                            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    SettingsCard(title: L("Âm thanh", "Sound")) {
                        SliderRow(title: L("Hiệu ứng", "Effects"), value: $settings.soundVolume)
                        SliderRow(title: L("Nhạc nền", "Music"), value: $settings.musicVolume)
                    }
                    SettingsCard(title: L("Quân cờ", "Pieces"), footnote: L("Áp dụng từ ván mới.", "Applies from the next game.")) {
                        Picker(L("Mẫu quân", "Piece style"), selection: $settings.pieceStyle) {
                            ForEach(PieceStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 14) {
                            ForEach(PlayerColor.allCases, id: \.self) { HorseToken(color: $0, size: 54) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    SettingsCard(title: L("Hoạt ảnh", "Animation")) {
                        Picker(L("Tốc độ", "Speed"), selection: $settings.animationSpeed) {
                            ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle(L("Giảm hiệu ứng (tắt pháo giấy, rung bàn, zoom khi đá quân)", "Reduce effects (no confetti, board shake or capture zoom)"), isOn: $settings.reducedEffects)
                        Toggle(L("Tự đi khi chỉ có một lựa chọn (kể cả ra quân)", "Move automatically when there is nothing to choose (including releasing a piece)"), isOn: $settings.autoMoveSingleOption)
                    }
                    #if os(macOS)
                    SettingsCard(title: L("Cửa sổ", "Window")) {
                        Toggle(L("Mở toàn màn hình khi khởi động", "Start in full screen"), isOn: $settings.startInFullScreen)
                    }
                    #endif
                    SettingsCard(title: L("Luật chơi", "Rules"), footnote: L("Áp dụng từ ván mới.", "Applies from the next game.")) {
                        Picker(L("Bộ luật", "Rule set"), selection: $settings.rulesPreset) {
                            ForEach(RulesPreset.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        RulesEditor(rules: $settings.rules)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: Device.isPhone ? 760 : 620)

            Button(L("Xong", "Done")) {
                coordinator.click()
                coordinator.showMainMenu()
            }
            .buttonStyle(ChunkyButtonStyle(tint: .player(.green)))
            .frame(width: 220)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, Device.isPhone ? 10 : 28)
        .padding(.horizontal, 40)
        .onChange(of: settings.soundVolume) { coordinator.applyAudioSettings() }
        .onChange(of: settings.musicVolume) { coordinator.applyAudioSettings() }
    }
}

private struct RulesEditor: View {
    @Binding var rules: RulesConfiguration

    var body: some View {
        Toggle(L("Chế độ nhanh: đổ 2 xúc xắc (dùng riêng từng viên hoặc cộng lại; ra đôi được đổ thêm)", "Speed mode: roll 2 dice (use each die separately or add them; doubles roll again)"), isOn: Binding(
            get: { rules.diceCount == 2 },
            set: { rules.diceCount = $0 ? 2 : 1 }))
        Toggle(L("Ra quân bằng 1 hoặc 6 (mặc định chỉ 6)", "Release a piece on 1 or 6 (default: 6 only)"), isOn: Binding(
            get: { rules.releaseValues.contains(1) },
            set: { rules.releaseValues = $0 ? [1, 6] : [6] }))
        Toggle(L("Đổ được 1 cũng được đổ thêm (chỉ áp dụng khi chơi 1 xúc xắc)", "Rolling a 1 also rolls again (one-die games only)"), isOn: Binding(
            get: { rules.bonusTurnValues.contains(1) },
            set: { rules.bonusTurnValues = $0 ? [1, 6] : [6] }))
        Toggle(L("Lần đổ thưởng thứ ba liên tiếp thì mất lượt", "A third bonus roll in a row loses the turn"), isOn: Binding(
            get: { rules.maxConsecutiveBonusRolls != nil },
            set: { rules.maxConsecutiveBonusRolls = $0 ? 3 : nil }))
        Toggle(L("Cho quân cùng màu đứng chung ô (thành hàng rào không bị đá)", "Let pieces of one colour share a square (a stack cannot be captured)"), isOn: $rules.allowStacking)
        Picker(L("Ô an toàn", "Safe squares"), selection: $rules.safeSquares) {
            Text(L("Không có", "None")).tag(SafeSquareRule.none)
            Text(L("Ô giữa mỗi cạnh", "Middle of each side")).tag(SafeSquareRule.startAndMidSquares)
        }
        Picker(L("Lên đích", "Entering home"), selection: $rules.homeEntry) {
            Text(L("Đổ số nào lên bậc đó", "Roll the number of the rung")).tag(HomeEntryRule.exactRungDirect)
            Text(L("Lần lượt từng bậc từ 1", "One rung at a time, from 1")).tag(HomeEntryRule.exactRungStepwise)
            Text(L("Đi theo số chấm (kiểu Ludo)", "Move by pip count (Ludo style)")).tag(HomeEntryRule.pipCount)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.baloo(22, .bold)).foregroundStyle(Color.ink)
            content
            if let footnote {
                Text(footnote).font(.baloo(13, .regular)).foregroundStyle(Color.ink.opacity(0.6))
            }
        }
        .font(.baloo(16, .medium))
        .foregroundStyle(Color.ink)
        .tint(.player(.green))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.panel)
            .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 4))
        .environment(\.colorScheme, .light)
    }
}

private struct SliderRow: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 90, alignment: .leading)
            Image(systemName: value < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 24)
            Slider(value: $value, in: 0...1)
            Text("\(Int((value * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}
