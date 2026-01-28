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
                            SidebarProjectRowView(project: project)
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
            
            Spacer()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(snagController.publisherStatus.contains("Listening") ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(snagController.publisherStatus)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                
                if !snagController.isSecurityEnabled {
                    Text("Security Disabled")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if let project = snagController.selectedProjectController,
                   let device = project.selectedDeviceController,
                   !device.isAuthenticated {
                    Button(action: {
                        enteredPIN = ""
                        showingPINPopover = true
                    }) {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text("Authorize Device".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    .tint(.blue)
                    .padding(.top, 4)
                    .popover(isPresented: $showingPINPopover) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter Security PIN".localized)
                                .font(.system(size: 12, weight: .bold))
                            
                            TextField("6-digit PIN", text: $enteredPIN)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 120)
                                .onChange(of: enteredPIN) { newValue in
                                    let filtered = newValue.filter { $0.isNumber }
                                    if filtered.count > 6 {
                                        enteredPIN = String(filtered.prefix(6))
                                    } else {
                                        enteredPIN = filtered
                                    }
                                }
                            
                            Text("Enter the PIN configured on your iOS/Android device to authorize this connection.".localized)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 200, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack {
                                Spacer()
                                Button("Authorize".localized) {
                                    if snagController.authorizeDevice(device, enteredPIN: enteredPIN) {
                                        showingPINPopover = false
                                    }
                                }
                                .buttonStyle(BorderedProminentButtonStyle())
                                .controlSize(.small)
                                .disabled(enteredPIN.count < 6)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: ThemeColor.deviceListBackgroundColor))
    }
    
    @State private var showingPINPopover = false
    @State private var enteredPIN = ""
}
