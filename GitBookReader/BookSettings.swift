import SwiftUI
import Combine

class BookSettings: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        case sepia
        
        var id: String { self.rawValue }
        var displayName: String {
            switch self {
            case .system: return "Hệ thống"
            case .light: return "Sáng"
            case .dark: return "Tối"
            case .sepia: return "Sepia (Mắt ấm)"
            }
        }
    }
    
    // Mức độ zoom Font (từ 0.5 đến 2.0)
    @Published var fontSizeMultiplier: Double {
        didSet {
            UserDefaults.standard.set(fontSizeMultiplier, forKey: "fontSizeMultiplier")
        }
    }
    
    // Theme đọc sách (Light/Dark/Sepia)
    @Published var readingTheme: Theme {
        didSet {
            UserDefaults.standard.set(readingTheme.rawValue, forKey: "readingTheme")
        }
    }
    
    init() {
        // Khởi tạo và đọc từ UserDefaults
        let savedFontSize = UserDefaults.standard.double(forKey: "fontSizeMultiplier")
        self.fontSizeMultiplier = savedFontSize > 0 ? savedFontSize : 1.0
        
        if let themeString = UserDefaults.standard.string(forKey: "readingTheme"),
           let theme = Theme(rawValue: themeString) {
            self.readingTheme = theme
        } else {
            self.readingTheme = .system
        }
    }
    
    // Dùng SwiftUI Color dynamic phụ thuộc vào Theme đang chọn
    var backgroundColor: Color {
        switch readingTheme {
        case .system: return Color(NSColor.textBackgroundColor)
        case .light: return .white
        case .dark: return Color(white: 0.1) // Đen tuyền đẹp hơn màu đen xám mặc định
        case .sepia: return Color(red: 251/255, green: 240/255, blue: 217/255) // Màu giấy vàng nhạt
        }
    }
    
    var preferredColorScheme: ColorScheme? {
        switch readingTheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        // Sepia dùng chung với giao diện Sáng của hệ thống
        case .sepia: return .light
        }
    }
}

// Helper to bridge NSColor/UIColor
#if os(iOS)
typealias NSColor = UIColor
extension UIColor {
    static var textBackgroundColor: UIColor { .systemBackground }
}
#endif
