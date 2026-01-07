import Foundation
import Combine

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "AppLanguage")
            loadBundle()
        }
    }
    
    private var bundle: Bundle?
    
    enum Language: String, CaseIterable, Identifiable {
        case auto = "auto"
        case english = "en"
        case japanese = "ja"
        case korean = "ko"
        case vietnamese = "vi"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .english: return "English"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .vietnamese: return "Vietnamese"
            }
        }
    }
    
    private init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage"),
           let language = Language(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .auto
        }
        loadBundle()
    }
    
    private func loadBundle() {
        if currentLanguage == .auto {
            bundle = nil
            return
        }
        
        if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = nil
        }
    }
    
    func localizedString(_ key: String) -> String {
        return bundle?.localizedString(forKey: key, value: nil, table: nil) ?? NSLocalizedString(key, comment: "")
    }
}

extension String {
    var localized: String {
        return LanguageManager.shared.localizedString(self)
    }
}
