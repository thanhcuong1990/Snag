import Cocoa
import SwiftUI

class TabToggleViewController: NSTitlebarAccessoryViewController {
    
    override func loadView() {
        let toggleView = TabToggleView()
        let hostingView = NSHostingView(rootView: toggleView)
        
        hostingView.layer?.backgroundColor = .clear
        
        self.view = hostingView
        
        // Slightly wider for Segmented Control
        self.view.frame = NSRect(x: 0, y: 0, width: 160, height: 40)
    }
}
