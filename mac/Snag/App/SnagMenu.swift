import Cocoa

class SnagMenu {
    static let shared = SnagMenu()
    
    private init() {
        // Observe language changes and rebuild the menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func languageDidChange() {
        buildMenu()
    }
    
    static func setup() {
        // Ensure shared instance exists to start observing
        _ = shared
        shared.buildMenu()
    }
    
    private func buildMenu() {
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
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find...".localized, action: #selector(FindActionResponder.performFindPanelAction(_:)), keyEquivalent: "f")

        // Request Menu
        let requestMenuItem = NSMenuItem()
        mainMenu.addItem(requestMenuItem)

        let requestMenu = NSMenu(title: "Request".localized)
        requestMenuItem.submenu = requestMenu

        let newDraftItem = NSMenuItem(title: "New Draft".localized,
                                      action: #selector(RequestMenuActions.newDraft(_:)),
                                      keyEquivalent: "n")
        newDraftItem.target = RequestMenuActions.shared
        requestMenu.addItem(newDraftItem)

        let sendItem = NSMenuItem(title: "Send".localized,
                                  action: #selector(RequestMenuActions.sendActiveDraft(_:)),
                                  keyEquivalent: "\r")
        sendItem.target = RequestMenuActions.shared
        requestMenu.addItem(sendItem)

        let cancelItem = NSMenuItem(title: "Cancel Send".localized,
                                    action: #selector(RequestMenuActions.cancelActiveDraft(_:)),
                                    keyEquivalent: ".")
        cancelItem.target = RequestMenuActions.shared
        requestMenu.addItem(cancelItem)

        requestMenu.addItem(NSMenuItem.separator())

        let duplicateItem = NSMenuItem(title: "Duplicate Draft".localized,
                                       action: #selector(RequestMenuActions.duplicateActiveDraft(_:)),
                                       keyEquivalent: "d")
        duplicateItem.withModifierMask([.command, .shift])
        duplicateItem.target = RequestMenuActions.shared
        requestMenu.addItem(duplicateItem)

        let closeItem = NSMenuItem(title: "Close Draft".localized,
                                   action: #selector(RequestMenuActions.closeActiveDraft(_:)),
                                   keyEquivalent: "w")
        closeItem.target = RequestMenuActions.shared
        requestMenu.addItem(closeItem)

        NSApp.mainMenu = mainMenu
    }
}

@MainActor
final class RequestMenuActions: NSObject, NSMenuItemValidation {
    static let shared = RequestMenuActions()

    @objc func newDraft(_ sender: Any?) {
        _ = ComposerController.shared.newBlankDraft()
        SnagController.shared.selectCompose()
    }

    @objc func sendActiveDraft(_ sender: Any?) {
        guard let draft = ComposerController.shared.activeDraft else { return }
        RequestSender.shared.send(draft)
    }

    @objc func cancelActiveDraft(_ sender: Any?) {
        guard let id = ComposerController.shared.activeDraftId else { return }
        RequestSender.shared.cancel(id)
    }

    @objc func duplicateActiveDraft(_ sender: Any?) {
        guard let draft = ComposerController.shared.activeDraft else { return }
        let copy = RequestDraftStore.shared.duplicate(draft)
        ComposerController.shared.open(copy)
    }

    @objc func closeActiveDraft(_ sender: Any?) {
        guard let id = ComposerController.shared.activeDraftId else { return }
        ComposerController.shared.close(id)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let onComposer = SnagController.shared.route == .compose
        let hasActive = ComposerController.shared.activeDraftId != nil
        let isSending: Bool = {
            guard let id = ComposerController.shared.activeDraftId else { return false }
            return RequestSender.shared.isSending(draftId: id)
        }()

        switch menuItem.action {
        case #selector(newDraft(_:)):
            return true
        case #selector(sendActiveDraft(_:)):
            guard onComposer, let draft = ComposerController.shared.activeDraft else { return false }
            return !draft.data.url.isEmpty && !isSending
        case #selector(cancelActiveDraft(_:)):
            return onComposer && isSending
        case #selector(duplicateActiveDraft(_:)),
             #selector(closeActiveDraft(_:)):
            return onComposer && hasActive
        default:
            return true
        }
    }
}

extension NSMenuItem {
    @discardableResult
    func withModifierMask(_ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        self.keyEquivalentModifierMask = mask
        return self
    }
}

@objc protocol FindActionResponder {
    func performFindPanelAction(_ sender: Any?)
}
