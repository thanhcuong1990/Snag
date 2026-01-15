import Cocoa
import SwiftUI

class LogsViewController: NSViewController {
    
    var viewModel: LogsViewModel!
    
    override func loadView() {
        self.view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let logsView = LogsView(viewModel: self.viewModel)
        let hostingView = NSHostingView(rootView: logsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        self.view.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: self.view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
}
