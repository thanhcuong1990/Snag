import SwiftUI
import Combine

class SearchViewModel: ObservableObject {
    static let shared = SearchViewModel()
    
    @Published var searchText: String = "" {
        didSet {
            UserDefaults.standard.set(searchText, forKey: addressFilterPersistenceKey)
        }
    }
    @Published var recentSearches: [String] = []
    
    // Indicates if we should show the suggestions/recent list
    @Published var showSuggestions: Bool = false
    
    // Mock list results (if meaningful to show)
    @Published var mockResults: [String] = []

    private var cancellables = Set<AnyCancellable>()
    private let recentSearchesKey = "RecentSearches"
    private let addressFilterPersistenceKey = "AddressFilterPersistence"
    
    private let mockData = ["api.hipvan.com", "cdn.hipvan.com", "auth.hipvan.com"]
    
    var onApplyFilter: ((String) -> Void)?
    
    init() {
        self.searchText = UserDefaults.standard.string(forKey: addressFilterPersistenceKey) ?? ""
        self.recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
        
        // Debounce logic
        $searchText
            .removeDuplicates()
            .debounce(for: .seconds(7), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performDebouncedSearch(text)
            }
            .store(in: &cancellables)
    }
    
    func performDebouncedSearch(_ text: String) {
        // Filter mock list
        if text.isEmpty {
            mockResults = []
        } else {
            mockResults = mockData.filter { $0.localizedCaseInsensitiveContains(text) }
        }
        
        // Apply to main app
        onApplyFilter?(text)
    }
    
    func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            addToRecents(text)
        }
        // Trigger immediate update if desired by user interaction, bypassing debounce?
        // The prompt says "Selecting a recent search autofills addressFilter and triggers a search."
        performDebouncedSearch(searchText) 
    }
    
    func selectRecentSearch(_ text: String) {
        searchText = text
        submitSearch()
        showSuggestions = false
    }
    
    private func addToRecents(_ text: String) {
        var current = recentSearches
        // Deduplicate
        current.removeAll { $0 == text }
        current.insert(text, at: 0)
        
        // Keep last 10
        if current.count > 10 {
            current = Array(current.prefix(10))
        }
        
        recentSearches = current
        saveRecents()
    }
    
    func deleteRecent(_ text: String) {
        recentSearches.removeAll { $0 == text }
        saveRecents()
    }
    
    func clearAllRecents() {
        recentSearches.removeAll()
        saveRecents()
    }
    
    private func saveRecents() {
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
}
