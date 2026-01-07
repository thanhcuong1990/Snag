import Cocoa

extension NSWindow {
    static func createMainWindow(contentViewController: NSViewController) -> NSWindow {
        // Calculate default window size based on screen dimensions (80% width, 70% height)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let defaultWidth = screenFrame.width * 0.8
        let defaultHeight = screenFrame.height * 0.7
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        
        window.title = "Snag - Network Debugger".localized
        
        // Observe language changes to update window title reactively
        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak window] _ in
            window?.title = "Snag - Network Debugger".localized
        }
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 600)
        
        // Add Tab Toggle to titlebar
        // let tabToggle = TabToggleViewController()
        // tabToggle.layoutAttribute = .trailing
        // window.addTitlebarAccessoryViewController(tabToggle)
        
        // Add Appearance Toggle to titlebar
        let appearanceToggle = AppearanceToggleViewController()
        appearanceToggle.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(appearanceToggle)
        
        // Add Language Toggle to titlebar
        let languageToggle = LanguageToggleViewController()
        languageToggle.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(languageToggle)
        
        window.contentViewController = contentViewController
        
        // Enable automatic window frame saving/restoring
        if !window.setFrameAutosaveName(SnagConstants.windowFrameAutosaveName) {
            // If no saved frame exists (first launch), use the default size and center
            window.setContentSize(NSSize(width: defaultWidth, height: defaultHeight))
            window.center()
        }
        
        return window
    }
}
