import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    @Published var appearanceMode: String {
        didSet {
            defaults.set(appearanceMode, forKey: SnagConstants.appearanceModeKey)
        }
    }
    
    @Published var addressFilter: String {
        didSet {
            defaults.set(addressFilter, forKey: SnagConstants.addressFilterPersistenceKey)
        }
    }
    
    @Published var recentSearches: [String] {
        didSet {
            defaults.set(recentSearches, forKey: SnagConstants.recentSearchesKey)
        }
    }
    
    private init() {
        self.appearanceMode = defaults.string(forKey: SnagConstants.appearanceModeKey) ?? SnagConstants.appearanceAuto
        self.addressFilter = defaults.string(forKey: SnagConstants.addressFilterPersistenceKey) ?? ""
        self.recentSearches = defaults.stringArray(forKey: SnagConstants.recentSearchesKey) ?? []
    }
    
    // Helper to add search and keep it within limits
    func addRecentSearch(_ text: String) {
        var current = recentSearches
        current.removeAll { $0 == text }
        current.insert(text, at: 0)
        
        if current.count > 10 {
            current = Array(current.prefix(10))
        }
        
        recentSearches = current
    }
    
    func removeRecentSearch(_ text: String) {
        recentSearches.removeAll { $0 == text }
    }
    
    func clearRecentSearches() {
        recentSearches = []
    }
}
