import SwiftUI

struct PacketsToolBar: View {
    @ObservedObject var viewModelWrapper: PacketsViewModelWrapper
    @ObservedObject var languageManager = LanguageManager.shared
    @FocusState.Binding var isAddressFilterFocused: Bool
    
    @ObservedObject private var searchViewModel = SearchViewModel.shared
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    filterInputs
                        .frame(width: geo.size.width * 0.5, alignment: .leading)
                    
                    categoryFilters.padding(.leading, 30)
                    
                    Spacer()
                    
                    trashButton
                }
                .frame(height: 32)
                
                if !domains.isEmpty {
                    domainRow
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(height: domains.isEmpty ? 32 : 60)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.controlBackgroundColor)
        .overlay(Divider(), alignment: .bottom)
        .onAppear {
            // Apply persistence on load
            viewModelWrapper.addressFilter = searchViewModel.searchText
            viewModelWrapper.updateFilters()
            
            // Link SearchViewModel to PacketsViewModelWrapper
            searchViewModel.onApplyFilter = { text in
                viewModelWrapper.addressFilter = text
                viewModelWrapper.updateFilters()
            }
        }
    }
    
    private var domainRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(domains, id: \.self) { domain in
                    domainChip(domain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .frame(height: 28)
    }
    
    private func domainChip(_ domain: String) -> some View {
        let isSelected = viewModelWrapper.addressFilter.lowercased() == domain.lowercased()
        return ZStack {
            // Reserve space
            Text(domain)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0)
            
            Text(domain)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(isSelected ? 0.18 : 0.12))
        .cornerRadius(4)
        .foregroundColor(isSelected ? .primary : .secondary)
        .contentShape(Rectangle())
        .onTapGesture {
            let text = domain.lowercased()
            // Update SearchViewModel (which updates wrapper via binding/callback)
            searchViewModel.searchText = text
            // Force immediate update
            searchViewModel.submitSearch()
            isAddressFilterFocused = true
        }
    }
    
    private var domains: [String] {
        var counts: [String: Int] = [:]
        
        let sourceItems: [SnagPacket]
        if let project = SnagController.shared.selectedProjectController,
           let device = project.selectedDeviceController {
            sourceItems = device.packets
        } else {
            sourceItems = SavedRequestsViewModel.shared.savedPackets
        }
        
        for item in sourceItems {
            guard let urlString = item.requestInfo?.url, 
                  let domain = urlString.extractDomain() else { continue }
            let main = domain.mainDomain()
            counts[main, default: 0] += 1
        }
        return counts.keys.sorted { a, b in
            let ca = counts[a, default: 0]
            let cb = counts[b, default: 0]
            if ca != cb { return ca > cb }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
    
    
    private var filterInputs: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            
            ZStack(alignment: .trailing) {
                TextField("Filter URL...".localized, text: $searchViewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11))
                    .focused($isAddressFilterFocused)
                    .onSubmit {
                        searchViewModel.submitSearch()
                    }
                    .padding(.trailing, 16)
                
                if !searchViewModel.searchText.isEmpty {
                    Button(action: {
                        searchViewModel.searchText = ""
                        searchViewModel.submitSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider().frame(height: 14)
            
            (Text("\(viewModelWrapper.items.count)")
                .foregroundColor(.primary) +
            Text(" requests".localized)
                .foregroundColor(.secondary))
                .font(.system(size: 11))
        }
    }
    
    private var categoryFilters: some View {
        HStack(spacing: 4) {
            categoryButton(.all)
            
            groupSeparator
            
            categoryButton(.fetchXHR)
            categoryButton(.media)
            
            groupSeparator
            
            HStack(spacing: 2) {
                categoryButton(.status1xx)
                categoryButton(.status2xx)
                categoryButton(.status3xx)
                categoryButton(.status4xx)
                categoryButton(.status5xx)
            }
        }
    }
    
    private var trashButton: some View {
        Button(action: { viewModelWrapper.clearPackets() }) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut("k", modifiers: .command)
    }
    
    private var groupSeparator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 4)
    }
    
    private func categoryButton(_ category: PacketFilterCategory) -> some View {
        let isSelected = viewModelWrapper.selectedCategory == category
        return ZStack {
            // Reserve space for the boldest state
            Text(category.localizedName)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0)
            
            Text(category.localizedName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isSelected ? Color.secondary.opacity(0.15) : Color.clear)
        .cornerRadius(3)
        .foregroundColor(isSelected ? .primary : .secondary)
        .onTapGesture {
            viewModelWrapper.selectedCategory = category
            viewModelWrapper.updateFilters()
        }
    }
}
