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
                    ForEach(Array(viewModelWrapper.items.enumerated()), id: \.element.packetId) { index, item in
                        PacketRowView(packet: item, isSelected: viewModelWrapper.selectedPacket === item, isAlternate: index % 2 != 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPacketSelect(item)
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
    }
}
