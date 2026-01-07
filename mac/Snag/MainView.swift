
import SwiftUI

struct MainView: View {
    @StateObject private var snagController = SnagController.shared
    @Environment(\.colorScheme) var colorScheme
    
    // Persistent state
    @AppStorage(SnagConstants.sidebarWidthKey) private var sidebarWidth: Double = 280
    @AppStorage(SnagConstants.packetsSplitRatioKey) private var packetsSplitRatio: Double = 0.5
    
    // Dragging state
    @State private var isDraggingSidebar: Bool = false
    @State private var isDraggingPackets: Bool = false
    
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
                
                // Content Area (Packets and Details)
                Group {
                    if snagController.selectedTab == .network {
                        GeometryReader { innerGeometry in
                            VStack(spacing: 0) {
                                PacketsViewControllerWrapper()
                                    .frame(height: max(100, innerGeometry.size.height * packetsSplitRatio))
                                
                                ResizableDivider(isDragging: $isDraggingPackets, orientation: .vertical)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                isDraggingPackets = true
                                                let newHeight = (innerGeometry.size.height * packetsSplitRatio) + value.translation.height
                                                let newRatio = newHeight / innerGeometry.size.height
                                                // Clamp ratio between 0.1 and 0.9
                                                packetsSplitRatio = min(max(newRatio, 0.1), 0.9)
                                            }
                                            .onEnded { _ in
                                                isDraggingPackets = false
                                            }
                                    )
                                
                                DetailViewControllerWrapper()
                                    .frame(maxHeight: .infinity)
                            }
                        }
                    } else {
                        LogsViewControllerWrapper()
                    }
                }
                .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - View Controller Wrappers

struct ProjectsViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> ProjectsViewController {
        let vc = ProjectsViewController()
        vc.viewModel = ProjectsViewModel()
        vc.viewModel?.register()
        vc.onProjectSelect = { project in
            SnagController.shared.selectedProjectController = project
        }
        return vc
    }
    func updateNSViewController(_ nsViewController: ProjectsViewController, context: Context) {}
}

struct DevicesViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> DevicesViewController {
        let vc = DevicesViewController()
        vc.viewModel = DevicesViewModel()
        vc.viewModel?.register()
        vc.onDeviceSelect = { device in
            SnagController.shared.selectedProjectController?.selectedDeviceController = device
        }
        return vc
    }
    func updateNSViewController(_ nsViewController: DevicesViewController, context: Context) {}
}

struct PacketsViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> PacketsViewController {
        let vc = PacketsViewController()
        vc.viewModel = PacketsViewModel()
        vc.viewModel?.register()
        vc.onPacketSelect = { packet in
            SnagController.shared.selectedProjectController?.selectedDeviceController?.select(packet: packet)
        }
        return vc
    }
    func updateNSViewController(_ nsViewController: PacketsViewController, context: Context) {}
}

struct DetailViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> DetailViewController {
        let vc = DetailViewController()
        vc.viewModel = DetailViewModel()
        vc.viewModel?.register()
        return vc
    }
    func updateNSViewController(_ nsViewController: DetailViewController, context: Context) {}
}

struct LogsViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> LogsViewController {
        let vc = LogsViewController()
        vc.viewModel = LogsViewModel()
        vc.viewModel.register()
        return vc
    }
    func updateNSViewController(_ nsViewController: LogsViewController, context: Context) {}
}
