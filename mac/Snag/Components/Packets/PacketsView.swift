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
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: 
                    VStack(spacing: 0) {
                        PacketsColumnHeaders(viewModelWrapper: viewModelWrapper)
                        Divider()
                    }
                ) {
                    ForEach(Array(viewModelWrapper.items.enumerated()), id: \.element.id) { index, item in
                        PacketRowView(packet: item, isSelected: viewModelWrapper.selectedPacket === item, isAlternate: index % 2 != 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPacketSelect(item)
                            }
                            .onRightClick {
                                onPacketSelect(item)
                            }
                            .contextMenu {
                                Button(NSLocalizedString("Copy cURL", comment: "Copy cURL context menu item")) {
                                    onPacketSelect(item)
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
                                        onPacketSelect(item)
                                        SavedRequestsViewModel.shared.save(packet: item)
                                    }
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 4)
            .animation(.easeOut(duration: 0.2), value: viewModelWrapper.items)
        }
        .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
    }
}
