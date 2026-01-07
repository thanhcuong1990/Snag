import Cocoa

struct SnagMenu {
    static func setup() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Snag".localized, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let updatesItem = NSMenuItem(title: "Check for Updates...".localized, action: #selector(SparkleManager.checkForUpdates), keyEquivalent: "")
        updatesItem.target = SparkleManager.shared
        appMenu.addItem(updatesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Snag".localized, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others".localized, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.withModifierMask([.command, .option])
        
        appMenu.addItem(withTitle: "Show All".localized, action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Snag".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: "Edit".localized)
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Undo".localized, action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo".localized, action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut".localized, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy".localized, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste".localized, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All".localized, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}

extension NSMenuItem {
    @discardableResult
    func withModifierMask(_ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        self.keyEquivalentModifierMask = mask
        return self
    }
}
