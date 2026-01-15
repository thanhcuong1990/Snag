import SwiftUI

struct MainView: View {
    @StateObject private var snagController = SnagController.shared
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    // Persistent state
    @AppStorage(SnagConstants.sidebarWidthKey) private var sidebarWidth: Double = 280
    
    // Dragging state
    @State private var isDraggingSidebar: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Unified Sidebar (Projects + Devices)
                SidebarView()
                    .frame(width: max(200, min(sidebarWidth, 500))) // Clamp sidebar width
                
                // Resizable Divider for Sidebar
                ResizableDivider(isDragging: $isDraggingSidebar, orientation: .horizontal)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingSidebar = true
                                let newWidth = sidebarWidth + value.translation.width
                                // Clamp sidebar width between 200 and 500
                                sidebarWidth = max(200, min(newWidth, 500))
                            }
                            .onEnded { _ in
                                isDraggingSidebar = false
                            }
                    )
                
                Group {
                    // Logic: Show Logs ONLY if a project is selected AND the Logs tab is active.
                    // Otherwise (Network tab or Saved Requests mode), show the Packets/Detail split view.
                    if snagController.selectedProjectController != nil && snagController.selectedTab == .logs {
                         LogsViewControllerWrapper()
                    } else {
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
