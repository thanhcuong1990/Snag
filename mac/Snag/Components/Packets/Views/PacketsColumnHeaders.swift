import SwiftUI

struct PacketsColumnHeaders: View {
    @ObservedObject var viewModelWrapper: PacketsViewModelWrapper
    
    var body: some View {
        HStack(spacing: 0) {
            Text("Code")
                .padding(.leading, 8)
                .frame(width: 75, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            Text("Method")
                .padding(.leading, 8)
                .frame(width: 60, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            Text("URL")
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            Text("Duration")
                .padding(.leading, 8)
                .frame(width: 70, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            Text("Request")
                .padding(.leading, 8)
                .frame(width: 70, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            Text("Response")
                .padding(.leading, 8)
                .frame(width: 70, alignment: .leading)
                .overlay(headerSeparator, alignment: .trailing)
            
            // Sortable Time column
            Button(action: { viewModelWrapper.toggleSortOrder() }) {
                HStack(spacing: 4) {
                    Text("Time")
                    Image(systemName: viewModelWrapper.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.leading, 8)
                .frame(width: 100, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondaryLabelColor)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Color.controlBackgroundColor)
    }
    
    private var headerSeparator: some View {
        Rectangle()
            .fill(Color.secondaryLabelColor.opacity(0.2))
            .frame(width: 1, height: 12)
    }
}
