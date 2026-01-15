import Cocoa
import SwiftUI

class ViewController: BaseViewController {

    private var hostingView: NSHostingView<MainView>?
    
    override func setup() {
        _ = SnagController.shared
        
        let mainView = MainView()
        let hostingView = NSHostingView(rootView: mainView)
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


