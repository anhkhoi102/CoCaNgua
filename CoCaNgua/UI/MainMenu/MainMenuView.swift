import GameCore
import SwiftUI

struct MainMenuView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        if Device.isPhone {
            // iPhone nằm ngang: logo bên trái, các nút bên phải.
            HStack(spacing: 36) {
                LogoView().scaleEffect(0.86)
                VStack(spacing: 16) {
                    buttons
                    version
                }
                .frame(width: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 26) {
                Spacer(minLength: 20)
                LogoView()
                VStack(spacing: 16) { buttons }
                    .frame(width: 300)
                Spacer(minLength: 20)
                version.padding(.bottom, 14)
            }
            .padding(.horizontal, 40)
        }
    }

    private var version: some View {
        Text(L("Phiên bản \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"))
            .font(.baloo(12, .regular))
            .foregroundStyle(.white.opacity(0.5))
    }

    @ViewBuilder private var buttons: some View {
            Group {
                Button(L("Chơi đơn", "Single player")) {
                    coordinator.click()
                    coordinator.showSinglePlayerSetup()
                }
                .buttonStyle(ChunkyButtonStyle(tint: .player(.red)))

                Button(L("Chơi mạng", "Online")) {
                    coordinator.click()
                    coordinator.showOnlineLobby()
                }
                .buttonStyle(ChunkyButtonStyle(tint: .player(.blue)))

                Button(L("Cài đặt", "Settings")) {
                    coordinator.click()
                    coordinator.showSettings()
                }
                .buttonStyle(ChunkyButtonStyle(tint: .player(.green)))

                #if os(macOS)
                Button(L("Thoát", "Quit")) { coordinator.quit() }
                    .buttonStyle(ChunkyButtonStyle(prominent: false))
                #endif
            }
    }
}

/// Logo trò chơi: ba chữ "Cờ", "Cá", "Ngựa" trên ba mảnh ghép nhiều màu xếp lệch nhau, bốn quân bốn màu đứng phía trên
/// và hai viên xúc xắc ở hai bên.
struct LogoView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                HStack(alignment: .bottom, spacing: -6) {
                    DiceView(face: 6, tilt: -16, rolling: false, tint: .player(.green), size: 58)
                        .padding(.bottom, 6)
                        .padding(.trailing, 14)
                    wordTile("Cờ", color: .red, angle: -6, lift: 0)
                    wordTile("Cá", color: .yellow, angle: 4, lift: 16)
                    wordTile("Ngựa", color: .blue, angle: -3, lift: 2)
                    DiceView(face: 1, tilt: 14, rolling: false, tint: .player(.red), size: 46)
                        .padding(.bottom, 54)
                        .padding(.leading, 12)
                }
                .padding(.top, 92)
                // Bốn quân đứng trên mép các mảnh chữ, quân giữa nhô cao hơn.
                HStack(alignment: .bottom, spacing: 26) {
                    piece(.red, height: 104, angle: -8)
                    piece(.yellow, height: 124, angle: -2)
                    piece(.green, height: 124, angle: 3)
                    piece(.blue, height: 104, angle: 9)
                }
            }
            Text(L("Trò chơi tuổi thơ, phiên bản mới", "The childhood classic, made new"))
                .font(.baloo(17, .semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.panel).shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 3))
        }
    }

    private func wordTile(_ word: String, color: PlayerColor, angle: Double, lift: CGFloat) -> some View {
        Text(word)
            .font(.baloo(82, .heavy))
            .foregroundStyle(.white)
            .shadow(color: Color(platform: Theme.darkColor(color)), radius: 0, x: 0, y: 4)
            .padding(.horizontal, 22)
            .padding(.top, 2)
            .padding(.bottom, -4)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(platform: Theme.darkColor(color)))
                        .offset(y: 9)
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Color(platform: Theme.color(color)).opacity(0.92), Color(platform: Theme.color(color))],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 4)
                }
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 10)
            }
            .rotationEffect(.degrees(angle))
            .offset(y: -lift)
    }

    private func piece(_ color: PlayerColor, height: CGFloat, angle: Double) -> some View {
        Image(coordinator.settings.pieceStyle.imageName(for: color))
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.30), radius: 3, x: 3, y: 5)
            .rotationEffect(.degrees(angle), anchor: .bottom)
    }
}

/// Hình quân dùng trong giao diện SwiftUI: cùng ảnh quân với trên bàn (theo kiểu quân đang chọn), đặt trên huy hiệu tròn.
struct HorseToken: View {
    @Environment(AppCoordinator.self) private var coordinator
    var color: PlayerColor
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(platform: Theme.darkColor(color)))
            Circle().fill(Color(platform: Theme.lightColor(color))).padding(size * 0.07)
            Image(coordinator.settings.pieceStyle.imageName(for: color))
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.92, height: size * 0.92)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: size * 0.07)
    }
}
