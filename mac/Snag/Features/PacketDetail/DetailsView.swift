import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModelWrapper: DetailViewModelWrapper
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    @AppStorage(SnagConstants.requestTabPersistenceKey) private var requestTab: DetailType = .overview
    @AppStorage(SnagConstants.responseTabPersistenceKey) private var responseTab: DetailType = .responseHeaders
    
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
                    ResizableDivider(isDragging: $isDragging, orientation: .horizontal)
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
                Text("Request".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    TabButton(title: "Overview".localized, isSelected: requestTab == .overview) {
                        requestTab = .overview
                    }
                    TabButton(title: "Header".localized, isSelected: requestTab == .requestHeaders) {
                        requestTab = .requestHeaders
                    }
                    TabButton(title: "Query".localized, isSelected: requestTab == .requestParameters) {
                        requestTab = .requestParameters
                    }
                    TabButton(title: "Body".localized, isSelected: requestTab == .requestBody) {
                        requestTab = .requestBody
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Content - Lazy loaded by using conditional rendering
            Group {
                switch requestTab {
                case .overview:
                    OverviewView(packet: viewModelWrapper.packet)
                case .requestHeaders:
                    KeyValueListView(viewModel: requestHeadersViewModel)
                case .requestParameters:
                    KeyValueListView(viewModel: requestParametersViewModel)
                case .requestBody:
                    DataDetailView(viewModel: requestBodyViewModel)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var responsePane: some View {
        VStack(spacing: 0) {
            // Header with tabs in a single row
            HStack(spacing: 8) {
                Text("Response".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    TabButton(title: "Header".localized, isSelected: responseTab == .responseHeaders) {
                        responseTab = .responseHeaders
                    }
                    TabButton(title: "Body".localized, isSelected: responseTab == .responseBody) {
                        responseTab = .responseBody
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            // Content - Lazy loaded
            Group {
                switch responseTab {
                case .responseHeaders:
                    KeyValueListView(viewModel: responseHeadersViewModel)
                case .responseBody:
                    DataDetailView(viewModel: responseDataViewModel)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}


