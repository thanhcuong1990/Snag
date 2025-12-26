import SwiftUI

struct PacketsToolBar: View {
    @ObservedObject var viewModelWrapper: PacketsViewModelWrapper
    @FocusState.Binding var isAddressFilterFocused: Bool
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                filterInputs
                    .frame(width: geo.size.width * 0.5, alignment: .leading)
                
                categoryFilters.padding(.leading, 30)
                
                Spacer()
                
                trashButton
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.controlBackgroundColor)
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var filterInputs: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            
            TextField("Filter URL...", text: $viewModelWrapper.addressFilter)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 11))
                .focused($isAddressFilterFocused)
                .onChange(of: viewModelWrapper.addressFilter) { _ in viewModelWrapper.updateFilters() }
            
            Divider().frame(height: 14)
            
            TextField("Status", text: $viewModelWrapper.statusFilter)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(width: 45)
                .font(.system(size: 11))
                .onChange(of: viewModelWrapper.statusFilter) { _ in viewModelWrapper.updateFilters() }
            
            Divider().frame(height: 14)
            
            TextField("Method", text: $viewModelWrapper.methodFilter)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(width: 45)
                .font(.system(size: 11))
                .onChange(of: viewModelWrapper.methodFilter) { _ in viewModelWrapper.updateFilters() }
            
            Divider().frame(height: 14)
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
        return Text(category.rawValue)
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
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
