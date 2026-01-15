import Cocoa
import SwiftUI

class LanguageToggleViewController: NSTitlebarAccessoryViewController {
    
    override func loadView() {
        let toggleView = LanguageToggleView()
        let hostingView = NSHostingView(rootView: toggleView)
        
        // Ensure the hostingView doesn't have a background to blend into the title bar
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.view = hostingView
        
        // The title bar accessory needs a specific size. 
        // We set a reasonable width to accommodate language names.
        self.view.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
    }
}
