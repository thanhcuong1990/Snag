import Cocoa
import SwiftUI

class PacketsViewController: BaseViewController {

    var viewModel: PacketsViewModel?
    var onPacketSelect : ((SnagPacket?) -> ())?

    private var hostingView: NSHostingView<PacketsView>?
    private var keyMonitor: Any?

    override func setup() {

        guard let viewModel = self.viewModel else { return }

        let packetsView = PacketsView(viewModelWrapper: PacketsViewModelWrapper(viewModel: viewModel), onPacketSelect: { [weak self] item in
            self?.onPacketSelect?(item)
        })

        let hostingView = NSHostingView(rootView: packetsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: self.view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.hostingView = hostingView

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126:
                NotificationCenter.default.post(name: .navigatePacketUp, object: nil)
                return nil
            case 125:
                NotificationCenter.default.post(name: .navigatePacketDown, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
