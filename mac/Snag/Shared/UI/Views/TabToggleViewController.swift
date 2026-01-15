import Cocoa
import SwiftUI

class TabToggleViewController: NSTitlebarAccessoryViewController {
    
    override func loadView() {
        let toggleView = TabToggleView()
        let hostingView = NSHostingView(rootView: toggleView)
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.view = hostingView
        self.view.translatesAutoresizingMaskIntoConstraints = false
    }
}
