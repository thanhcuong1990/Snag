import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModelWrapper: DetailViewModelWrapper
    @Environment(\.colorScheme) var colorScheme
    
    @State private var requestTab: DetailType = .overview
    @State private var responseTab: DetailType = .responseHeaders
    
    // Resizable split state
    @AppStorage(SnagConstants.detailsSplitRatioKey) private var splitRatio: Double = 0.5
    @State private var isDragging: Bool = false
    
    // Persistent ViewModels that stay alive and receive notifications
    @StateObject private var requestHeadersViewModel = RequestHeadersViewModel()
    @StateObject private var requestParametersViewModel = RequestParametersViewModel()
    @StateObject private var requestBodyViewModel = RequestBodyViewModel()
    @StateObject private var responseHeadersViewModel = ResponseHeadersViewModel()
    @StateObject private var responseDataViewModel = ResponseDataViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            DetailsTopBar(packet: viewModelWrapper.packet)
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // MARK: - Left Pane (Request)
                    requestPane
                        .frame(width: max(150, geometry.size.width * splitRatio - 4))
                    
                    // MARK: - Resizable Divider
                    ResizableDivider(isDragging: $isDragging)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    let newWidth = (geometry.size.width * splitRatio) + value.translation.width
                                    let newRatio = newWidth / geometry.size.width
                                    // Clamp between 20% and 80%
                                    splitRatio = min(max(newRatio, 0.2), 0.8)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                    
                    // MARK: - Right Pane (Response)
                    responsePane
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(DetailsTheme.backgroundColor)
    }
    
    // MARK: - Subviews
    
    private var requestPane: some View {
        VStack(spacing: 0) {
            // Header with tabs in a single row
            HStack(spacing: 8) {
                Text("Request")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    TabButton(title: "Overview", isSelected: requestTab == .overview) {
                        requestTab = .overview
                    }
                    TabButton(title: "Header", isSelected: requestTab == .requestHeaders) {
                        requestTab = .requestHeaders
                    }
                    TabButton(title: "Query", isSelected: requestTab == .requestParameters) {
                        requestTab = .requestParameters
                    }
                    TabButton(title: "Body", isSelected: requestTab == .requestBody) {
                        requestTab = .requestBody
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Content - using ZStack with opacity to keep views alive
            ZStack {
                OverviewView(packet: viewModelWrapper.packet)
                    .opacity(requestTab == .overview ? 1 : 0)
                    .allowsHitTesting(requestTab == .overview)
                
                KeyValueListView(viewModel: requestHeadersViewModel)
                    .opacity(requestTab == .requestHeaders ? 1 : 0)
                    .allowsHitTesting(requestTab == .requestHeaders)
                
                KeyValueListView(viewModel: requestParametersViewModel)
                    .opacity(requestTab == .requestParameters ? 1 : 0)
                    .allowsHitTesting(requestTab == .requestParameters)
                
                DataDetailView(viewModel: requestBodyViewModel)
                    .opacity(requestTab == .requestBody ? 1 : 0)
                    .allowsHitTesting(requestTab == .requestBody)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var responsePane: some View {
        VStack(spacing: 0) {
            // Header with tabs in a single row
            HStack(spacing: 8) {
                Text("Response")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    TabButton(title: "Header", isSelected: responseTab == .responseHeaders) {
                        responseTab = .responseHeaders
                    }
                    TabButton(title: "Body", isSelected: responseTab == .responseBody) {
                        responseTab = .responseBody
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Content - using ZStack with opacity to keep views alive
            ZStack {
                KeyValueListView(viewModel: responseHeadersViewModel)
                    .opacity(responseTab == .responseHeaders ? 1 : 0)
                    .allowsHitTesting(responseTab == .responseHeaders)
                
                DataDetailView(viewModel: responseDataViewModel)
                    .opacity(responseTab == .responseBody ? 1 : 0)
                    .allowsHitTesting(responseTab == .responseBody)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Resizable Divider

private struct ResizableDivider: View {
    @Binding var isDragging: Bool
    @State private var isHovering: Bool = false
    
    var body: some View {
        Rectangle()
            .fill(isDragging || isHovering ? Color.accentColor : Color.gray.opacity(0.3))
            .frame(width: isDragging || isHovering ? 4 : 1)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
