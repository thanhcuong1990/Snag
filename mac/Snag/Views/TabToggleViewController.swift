import Cocoa
import SwiftUI

class TabToggleViewController: NSTitlebarAccessoryViewController {
    
    override func loadView() {
        let toggleView = TabToggleView()
        let hostingView = NSHostingView(rootView: toggleView)
        
        hostingView.layer?.backgroundColor = .clear
        
        self.view = hostingView
        self.view.translatesAutoresizingMaskIntoConstraints = false
    }
}
