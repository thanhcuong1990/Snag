import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    private var screenParametersObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?

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

        // Mitigates QuartzCore `CA::OGL::new_metal_context` aborts seen after
        // sleep/wake or external-display reconfiguration: prompt AppKit to
        // recreate layer backing on the next runloop tick.
        registerDisplayResilienceObservers()

        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerDisplayResilienceObservers() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindowBacking()
        }

        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindowBacking()
        }
    }

    private func refreshWindowBacking() {
        guard let window else { return }
        // Defer one runloop tick so WindowServer finishes its own display
        // reconfiguration before we mark views dirty.
        DispatchQueue.main.async {
            window.contentView?.needsDisplay = true
            window.viewsNeedDisplay = true
            window.invalidateShadow()
        }
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
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(didWakeObserver)
        }
    }

    @objc func minimizeWindow(_ sender: Any?) {
        NSApp.hide(sender)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
