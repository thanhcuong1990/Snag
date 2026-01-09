import SwiftUI

struct SidebarView: View {
    @ObservedObject var snagController: SnagController = SnagController.shared
    @ObservedObject var searchViewModel = SearchViewModel.shared
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Title/Header
            Text("REMOTE".localized)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondaryLabelColor)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if snagController.projectControllers.isEmpty {
                        EmptySidebarState()
                    } else {
                        ForEach(snagController.projectControllers, id: \.self) { project in
                            VStack(alignment: .leading, spacing: 12) {
                                SidebarProjectHeader(project: project)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(project.deviceControllers, id: \.self) { device in
                                        SidebarDeviceRow(
                                            device: device,
                                            isSelected: snagController.selectedProjectController == project && project.selectedDeviceController == device
                                        )
                                        .onTapGesture {
                                            snagController.selectedProjectController = project
                                            project.selectedDeviceController = device
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                
                // Saved Requests Section
                VStack(alignment: .leading, spacing: 0) {
                    Text("LOCAL".localized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondaryLabelColor)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Saved Requests".localized)
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                        .background(snagController.selectedProjectController == nil ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
                        .foregroundColor(snagController.selectedProjectController == nil ? .white : .secondary)
                        .onTapGesture {
                            snagController.selectedProjectController = nil 
                        }
                    }
                }
            }
            
            if !searchViewModel.recentSearches.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("RECENT SEARCHES".localized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondaryLabelColor)
                        Spacer()
                        Button(action: { searchViewModel.clearAllRecents() }) {
                            Text("Clear".localized)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondaryLabelColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(searchViewModel.recentSearches, id: \.self) { search in
                                RecentSearchRow(text: search, action: {
                                    searchViewModel.selectRecentSearch(search)
                                }, deleteAction: {
                                    searchViewModel.deleteRecent(search)
                                })
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: ThemeColor.deviceListBackgroundColor))
    }
}
