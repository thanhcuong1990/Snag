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
        .onReceive(NotificationCenter.default.publisher(for: .focusPacketSearch)) { _ in
            isAddressFilterFocused = true
        }
    }
    
    // MARK: - Subviews
    
    private var packetList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(
                    header:
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
                                    SavedPacketStore.shared.save(packet: item)
                                }
                            }
                        }
                    }
                }
            }
        }
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
