import Cocoa
import SwiftUI

class DevicesViewController: BaseViewController {

    var viewModel: DevicesViewModel?
    var onDeviceSelect : ((SnagDeviceController) -> ())?
    
    private var hostingView: NSHostingView<DevicesView>?
    
    override func setup() {
        
        guard let viewModel = self.viewModel else { return }
        
        let devicesView = DevicesView(viewModelWrapper: DevicesViewModelWrapper(viewModel: viewModel), onDeviceSelect: { [weak self] item in
            self?.onDeviceSelect?(item)
        })
        
        let hostingView = NSHostingView(rootView: devicesView)
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

