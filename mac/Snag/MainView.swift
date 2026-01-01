
import SwiftUI

struct MainView: View {
    @StateObject private var snagController = SnagController.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Unified Sidebar (Projects + Devices)
            SidebarView()
                .frame(width: 280)
            
            Divider()
            
            // Content Area (Packets and Details)
            Group {
                if snagController.selectedTab == .network {
                    VSplitView {
                        PacketsViewControllerWrapper()
                            .frame(minHeight: 200)
                        
                        DetailViewControllerWrapper()
                            .frame(minHeight: 200)
                    }
                } else {
                    LogsViewControllerWrapper()
                }
            }
            .background(Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor))
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
