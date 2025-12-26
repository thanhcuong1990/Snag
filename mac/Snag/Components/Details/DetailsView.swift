import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModelWrapper: DetailViewModelWrapper
    @Environment(\.colorScheme) var colorScheme
    
    @State private var requestTab: DetailType = .overview
    @State private var responseTab: DetailType = .responseHeaders
    
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
            
            HStack(spacing: 0) {
                // MARK: - Left Pane (Request)
                requestPane
                
                Divider()
                
                // MARK: - Right Pane (Response)
                responsePane
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
