import SwiftUI

enum SortOrder {
    case ascending   // Oldest first
    case descending  // Newest first
}

class PacketsViewModelWrapper: ObservableObject {
    @Published var items: [SnagPacket] = []
    @Published var selectedPacket: SnagPacket? = nil
    @Published var addressFilter: String = ""
    @Published var statusFilter: String = ""
    @Published var methodFilter: String = ""
    @Published var selectedCategory: PacketFilterCategory = .all
    @Published var sortOrder: SortOrder = .descending  // Default: newest first

    private var viewModel: PacketsViewModel?

    init(viewModel: PacketsViewModel?) {
        self.viewModel = viewModel
        self.addressFilter = viewModel?.addressFilterTerm ?? ""
        self.statusFilter = viewModel?.statusFilterTerm ?? ""
        self.methodFilter = viewModel?.methodFilterTerm ?? ""
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
    }
    
    func updateFilters() {
        viewModel?.addressFilterTerm = addressFilter
        viewModel?.statusFilterTerm = statusFilter
        viewModel?.methodFilterTerm = methodFilter
        viewModel?.categoryFilter = selectedCategory
    }
    
    func clearPackets() {
        viewModel?.clearPackets()
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
