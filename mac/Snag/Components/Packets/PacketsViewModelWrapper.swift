import SwiftUI

enum SortOrder {
    case ascending   // Oldest first
    case descending  // Newest first
}

class PacketsViewModelWrapper: ObservableObject {
    @Published var items: [SnagPacket] = []
    @Published var selectedPacket: SnagPacket? = nil
    @Published var addressFilter: String = ""
    @Published var selectedCategory: PacketFilterCategory = .all
    @Published var sortOrder: SortOrder = .descending  // Default: newest first
    @Published var isSavedMode: Bool = false

    private var viewModel: PacketsViewModel?

    init(viewModel: PacketsViewModel?) {
        self.viewModel = viewModel
        self.addressFilter = viewModel?.addressFilterTerm ?? ""
        self.selectedCategory = viewModel?.categoryFilter ?? .all
        self.update()

        viewModel?.onChange = { [weak self] in
            self?.update()
        }
    }

    func update() {
        let rawItems = viewModel?.items ?? []
        self.items = sortItems(rawItems)
        self.selectedPacket = viewModel?.selectedItem
        self.isSavedMode = viewModel?.isSavedMode ?? false
    }
    
    func updateFilters() {
        viewModel?.addressFilterTerm = addressFilter
        viewModel?.categoryFilter = selectedCategory
    }
    
    func clearPackets() {
        viewModel?.clearPackets()
    }
    
    func deletePacket(_ packet: SnagPacket) {
        viewModel?.deletePacket(packet)
    }
    
    func toggleSortOrder() {
        sortOrder = (sortOrder == .ascending) ? .descending : .ascending
        update()
    }
    
    private func sortItems(_ items: [SnagPacket]) -> [SnagPacket] {
        return items.sorted { a, b in
            let dateA = a.requestInfo?.startDate ?? Date.distantPast
            let dateB = b.requestInfo?.startDate ?? Date.distantPast
            
            switch sortOrder {
            case .ascending:
                return dateA < dateB
            case .descending:
                return dateB < dateA
            }
        }
    }
}
