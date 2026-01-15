import SwiftUI

struct PacketsView: View {
    @ObservedObject var viewModelWrapper: PacketsViewModelWrapper
    @Environment(\.colorScheme) var colorScheme
    var onPacketSelect: (SnagPacket) -> Void
    
    @FocusState private var isAddressFilterFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            PacketsToolBar(viewModelWrapper: viewModelWrapper, isAddressFilterFocused: $isAddressFilterFocused)
            packetList
        }
        .background(
            Button("") {
                isAddressFilterFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        )
    }
    
    // MARK: - Subviews
    
    private var packetList: some View {
        List {
            Section(header: 
                VStack(spacing: 0) {
                    PacketsColumnHeaders(viewModelWrapper: viewModelWrapper)
                    Divider()
                }
                .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
            ) {
                ForEach(Array(viewModelWrapper.items.enumerated()), id: \.element.id) { index, item in
                    PacketRowView(
                        packet: item,
                        isSelected: viewModelWrapper.selectedPacket === item,
                        isAlternate: index % 2 != 0
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .hideListRowSeparator()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPacketSelect(item)
                    }
                    .onRightClick {
                        onPacketSelect(item)
                    }
                    .contextMenu {
                        Button(NSLocalizedString("Copy cURL", comment: "Copy cURL context menu item")) {
                            if let curl = item.toCurlCommand() {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(curl, forType: .string)
                            }
                        }
                        
                        if viewModelWrapper.isSavedMode {
                            Button("Delete") {
                                viewModelWrapper.deletePacket(item)
                            }
                        } else {
                            Button("Save Request") {
                                SavedRequestsViewModel.shared.save(packet: item)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .padding(.vertical, 0)
        .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
    }
}

// MARK: - Extension

extension View {
    @ViewBuilder
    func hideListRowSeparator() -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }
}
