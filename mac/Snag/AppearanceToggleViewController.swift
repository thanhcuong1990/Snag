import Cocoa
import SwiftUI

class AppearanceToggleViewController: NSTitlebarAccessoryViewController {
    
    override func loadView() {
        let toggleView = AppearanceToggleView()
        let hostingView = NSHostingView(rootView: toggleView)
        
        // Ensure the hostingView doesn't have a background to blend into the title bar
        hostingView.layer?.backgroundColor = .clear
        
        self.view = hostingView
        
        // The title bar accessory needs a specific size
        self.view.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
    }
}
