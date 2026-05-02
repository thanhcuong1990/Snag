import SwiftUI

struct MainView: View {
    @StateObject private var snagController = SnagController.shared
    @StateObject private var composer = ComposerController.shared
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme

    // Persistent state
    @AppStorage(SnagConstants.sidebarWidthKey) private var sidebarWidth: Double = 280

    // Dragging state
    @State private var isDraggingSidebar: Bool = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Unified Sidebar (Projects + Devices + Drafts + Saved)
                SidebarView()
                    .frame(width: max(200, min(sidebarWidth, 500))) // Clamp sidebar width

                // Resizable Divider for Sidebar
                ResizableDivider(isDragging: $isDraggingSidebar, orientation: .horizontal)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingSidebar = true
                                let newWidth = sidebarWidth + value.translation.width
                                sidebarWidth = max(200, min(newWidth, 500))
                            }
                            .onEnded { _ in
                                isDraggingSidebar = false
                            }
                    )

                Group {
                    switch snagController.route {
                    case .logs:
                        LogsViewControllerWrapper()
                    case .compose:
                        ComposerView()
                    case .saved, .network:
                        PacketSplitView()
                    }
                }
                .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
}
