import SwiftUI

// Lớp đệm giữa macOS (AppKit) và iOS (UIKit): phần còn lại của ứng dụng chỉ dùng các tên ở đây.

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformViewController = NSViewController
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformViewController = UIViewController

extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Trộn màu theo tỉ lệ, cùng tên với hàm của NSColor.
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor? {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1), other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        let mix = { (a: CGFloat, b: CGFloat) in a + (b - a) * fraction }
        return UIColor(red: mix(r1, r2), green: mix(g1, g2), blue: mix(b1, b2), alpha: mix(a1, a2))
    }
}
#endif

extension Color {
    init(platform color: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}

/// Loại thiết bị đang chạy, để chọn bố cục.
enum Device {
    /// iPhone (màn hình ngang, thấp). Trên macOS bản Debug có thể giả lập bằng biến môi trường COCANGUA_PHONE_PREVIEW
    /// để soát bố cục iPhone mà không cần simulator.
    static let isPhone: Bool = {
        #if os(iOS)
        return true
        #else
        return ProcessInfo.processInfo.environment["COCANGUA_PHONE_PREVIEW"] != nil
        #endif
    }()

    /// Giao diện được thiết kế theo điểm của macOS; trên iPhone toàn bộ được thu nhỏ theo hệ số này.
    static let uiScale: CGFloat = isPhone ? 0.74 : 1
}

/// Dựng nội dung ở kích thước lớn hơn màn hình rồi thu nhỏ cho vừa (chỉ trên iPhone), để dùng chung một bố cục.
struct ScaledCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if Device.uiScale == 1 {
            content
        } else {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.width / Device.uiScale, height: proxy.size.height / Device.uiScale)
                    .scaleEffect(Device.uiScale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

extension View {
    /// Nút dạng liên kết (chữ có màu, không khung).
    @ViewBuilder func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}

/// Trên iPhone màn hình thấp nên nội dung dài được cho cuộn; trên macOS giữ nguyên.
struct PhoneScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if Device.isPhone {
            ScrollView { content.padding(.bottom, 6) }
        } else {
            content
        }
    }
}

extension Font {
    /// Tiêu đề màn hình; nhỏ hơn trên iPhone để dành chỗ cho nội dung.
    static var screenTitle: Font { .baloo(Device.isPhone ? 30 : 44, .heavy) }
}
