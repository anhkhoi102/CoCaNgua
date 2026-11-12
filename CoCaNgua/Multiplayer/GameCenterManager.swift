import SwiftUI
@preconcurrency import GameKit
import Observation

/// Đăng nhập Game Center và theo dõi trạng thái đăng nhập.
///
/// Trên macOS, `authenticateHandler` trả về một `NSViewController` khi cần người dùng đăng nhập;
/// nó được trình bày qua `GKDialogController` (cách của macOS, khác iOS).
@MainActor
@Observable
final class GameCenterManager {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn(name: String)
        /// Không dùng được Game Center; kèm lý do để hiển thị.
        case unavailable(String)
    }

    private(set) var status: Status = .signedOut
    /// Gọi mỗi khi đăng nhập thành công.
    var onSignedIn: (() -> Void)?

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    func signIn() {
        if GKLocalPlayer.local.isAuthenticated {
            finish(errorMessage: nil)
            return
        }
        guard status != .signingIn else { return }
        status = .signingIn
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let viewController {
                    Self.present(viewController)
                } else {
                    self?.finish(errorMessage: message)
                }
            }
        }
        // Khi app chưa được cấp quyền Game Center (bản chưa ký, simulator), hệ thống có thể không bao giờ
        // gọi lại; không để màn hình treo ở "Đang đăng nhập" mãi. Nếu sau đó hệ thống trả lời thì `finish` vẫn cập nhật.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.status == .signingIn else { return }
            self.status = .unavailable(L("Game Center không phản hồi. Hãy kiểm tra đã đăng nhập Game Center trong Cài đặt của máy, rồi thử lại.", "Game Center did not respond. Check that you are signed in to Game Center in the device's Settings, then try again."))
        }
    }

    private func finish(errorMessage: String?) {
        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            if player.isMultiplayerGamingRestricted {
                status = .unavailable(L("Tài khoản Game Center này bị hạn chế chơi mạng.", "This Game Center account is restricted from multiplayer."))
            } else {
                status = .signedIn(name: player.displayName)
                onSignedIn?()
            }
        } else {
            status = .unavailable(errorMessage ?? L("Chưa đăng nhập Game Center. Hãy đăng nhập trong Cài đặt hệ thống → Game Center.", "Not signed in to Game Center. Sign in under System Settings → Game Center."))
        }
    }

    #if os(macOS)
    static func present(_ viewController: NSViewController) {
        let dialog = GKDialogController.shared()
        dialog.parentWindow = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        if let gameCenterController = viewController as? (NSViewController & GKViewController) {
            dialog.present(gameCenterController)
        } else {
            dialog.parentWindow?.contentViewController?.presentAsSheet(viewController)
        }
    }

    static func dismissDialog() {
        GKDialogController.shared().dismiss(NSApp as Any)
    }
    #else
    /// Màn hình Game Center đang mở (đăng nhập, mời bạn), để đóng lại khi xong.
    private static weak var presented: UIViewController?

    static func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        presented = viewController
        top?.present(viewController, animated: true)
    }

    static func dismissDialog() {
        presented?.dismiss(animated: true)
        presented = nil
    }
    #endif
}
