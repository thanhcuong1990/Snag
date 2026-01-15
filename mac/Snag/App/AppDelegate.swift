import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize core controller
        _ = SnagController.shared
        
        // Initialize Sparkle for auto-updates
        _ = SparkleManager.shared
        
        // Setup application menu
        SnagMenu.setup()
        
        // Create and configure main window using helper extension
        window = NSWindow.createMainWindow(contentViewController: ViewController())
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Apply persisted appearance
        applyPersistedAppearance()
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func applyPersistedAppearance() {
        let appearanceValue = SettingsManager.shared.appearanceMode
        
        switch appearanceValue {
        case SnagConstants.appearanceLight:
            NSApp.appearance = NSAppearance(named: .aqua)
        case SnagConstants.appearanceDark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
