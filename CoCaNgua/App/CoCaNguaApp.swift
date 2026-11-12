import SwiftUI

/// Điểm vào ứng dụng Cờ Cá Ngựa.
@main
struct CoCaNguaApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup("Cờ Cá Ngựa") {
            #if os(macOS)
            RootView()
                .environment(coordinator)
                .frame(minWidth: Device.isPhone ? 852 : 960, minHeight: Device.isPhone ? 393 : 680)
            #else
            RootView()
                .environment(coordinator)
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: Device.isPhone ? 852 : 1180, height: Device.isPhone ? 393 : 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            TableBackground()
            ScaledCanvas {
                screen
                    // Đổi ngôn ngữ thì dựng lại toàn bộ màn hình để mọi chuỗi được đọc lại.
                    .id(coordinator.settings.language)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.screen)
        .task {
            coordinator.bootstrap()
            #if os(macOS)
            if coordinator.settings.startInFullScreen, let window = NSApp.windows.first, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            #endif
            await SnapshotTool.runIfRequested(coordinator: coordinator)
        }
    }

    @ViewBuilder private var screen: some View {
        ZStack {
            switch coordinator.screen {
            case .mainMenu:
                MainMenuView().transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .singlePlayerSetup:
                SinglePlayerSetupView().transition(.opacity.combined(with: .move(edge: .trailing)))
            case .onlineLobby:
                OnlineLobbyView().transition(.opacity.combined(with: .move(edge: .trailing)))
            case .settings:
                SettingsView().transition(.opacity.combined(with: .move(edge: .trailing)))
            case .game:
                if let session = coordinator.session {
                    // Mỗi ván có cảnh SpriteKit riêng; đổi id để SwiftUI dựng lại SpriteView thay vì giữ cảnh của ván trước.
                    GameView(session: session).id(ObjectIdentifier(session)).transition(.opacity)
                }
            }
        }
    }
}
