import Foundation

/// Ngôn ngữ hiển thị trong game. Thanh menu của macOS luôn là tiếng Anh và không phụ thuộc lựa chọn này.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case vi, en
    var id: String { rawValue }

    /// Tên ngôn ngữ viết bằng chính ngôn ngữ đó, để ai cũng tìm được lựa chọn của mình.
    var title: String {
        switch self {
        case .vi: "Tiếng Việt"
        case .en: "English"
        }
    }
}

enum Localization {
    /// Ngôn ngữ đang dùng. Chỉ `GameSettings` ghi (trên luồng chính); giao diện được dựng lại khi giá trị đổi.
    nonisolated(unsafe) static var language: AppLanguage = .vi
}

/// Chuỗi hiển thị theo ngôn ngữ đang chọn. Hai bản dịch nằm cạnh nhau tại nơi dùng nên không thể lệch khoá;
/// chỉ bản được chọn mới được tính (kể cả phần nội suy).
func L(_ vi: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String {
    Localization.language == .vi ? vi() : en()
}
