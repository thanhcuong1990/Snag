import Cocoa
import SwiftUI

class PacketsViewController: BaseViewController {
    
    var viewModel: PacketsViewModel?
    var onPacketSelect : ((SnagPacket?) -> ())?
    
    private var hostingView: NSHostingView<PacketsView>?
    
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
    }
}

