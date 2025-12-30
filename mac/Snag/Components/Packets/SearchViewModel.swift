import SwiftUI
import Combine

class SearchViewModel: ObservableObject {
    static let shared = SearchViewModel()
    
    @Published var searchText: String = "" {
        didSet {
            SettingsManager.shared.addressFilter = searchText
        }
    }
    @Published var recentSearches: [String] = [] {
        didSet {
            SettingsManager.shared.recentSearches = recentSearches
        }
    }
    
    // Indicates if we should show the suggestions/recent list
    @Published var showSuggestions: Bool = false
    
    // List of suggested domains from traffic
    @Published var suggestions: [String] = []

    private var cancellables = Set<AnyCancellable>()
    
    var onApplyFilter: ((String) -> Void)?
    
    init() {
        self.searchText = SettingsManager.shared.addressFilter
        self.recentSearches = SettingsManager.shared.recentSearches
        
        // Debounce logic
        $searchText
            .removeDuplicates()
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performDebouncedSearch(text)
            }
            .store(in: &cancellables)
    }
    
    func performDebouncedSearch(_ text: String) {
        // Filter traffic domains for suggestions
        if text.isEmpty {
            suggestions = []
        } else {
            let activeDomains = getActiveDomains()
            suggestions = activeDomains.filter { $0.localizedCaseInsensitiveContains(text) }
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
        SettingsManager.shared.addRecentSearch(text)
        self.recentSearches = SettingsManager.shared.recentSearches
    }
    
    func deleteRecent(_ text: String) {
        SettingsManager.shared.removeRecentSearch(text)
        self.recentSearches = SettingsManager.shared.recentSearches
    }
    
    func clearAllRecents() {
        SettingsManager.shared.clearRecentSearches()
        self.recentSearches = SettingsManager.shared.recentSearches
    }
    
    private func getActiveDomains() -> [String] {
        var counts: [String: Int] = [:]
        let packets = SnagController.shared.selectedProjectController?.selectedDeviceController?.packets ?? []
        
        for packet in packets {
            guard let urlString = packet.requestInfo?.url,
                  let domain = urlString.extractDomain() else { continue }
            let main = domain.mainDomain()
            counts[main, default: 0] += 1
        }
        
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }
}
