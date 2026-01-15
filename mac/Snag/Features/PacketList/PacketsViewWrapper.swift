import SwiftUI

struct PacketsViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> PacketsViewController {
        let vc = PacketsViewController()
        vc.viewModel = PacketsViewModel()
        vc.viewModel?.register()
        vc.onPacketSelect = { packet in
            if let project = SnagController.shared.selectedProjectController,
               let device = project.selectedDeviceController {
                device.select(packet: packet)
            } else {
                SnagController.shared.selectedSavedPacket = packet
            }
        }
        return vc
    }
    func updateNSViewController(_ nsViewController: PacketsViewController, context: Context) {}
}
