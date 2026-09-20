import Cocoa

/// Menu commands for mirroring captured traffic to a folder on disk.
@MainActor
final class FixtureCaptureMenuActions: NSObject, NSMenuItemValidation {

    static let shared = FixtureCaptureMenuActions()

    enum Tag: Int {
        case toggleRecording = 8100
        case chooseFolder = 8101
        case hostFilter = 8102
        case revealFolder = 8103
    }

    @objc func toggleRecording(_ sender: Any?) {
        let service = FixtureCaptureService.shared
        if service.isRecording {
            service.stop()
            return
        }
        if service.destination == nil {
            chooseFolder(sender)
        }
        guard service.destination != nil else { return }
        service.start()
    }

    @objc func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose".localized
        panel.message = "Captured responses are written here, one file per call.".localized
        if panel.runModal() == .OK {
            FixtureCaptureService.shared.destination = panel.url
        }
    }

    @objc func editHostFilter(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Only capture URLs containing".localized
        alert.informativeText = "Leave empty to capture every request.".localized
        alert.addButton(withTitle: "Save".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = FixtureCaptureService.shared.hostFilter
        field.placeholderString = "communa.sg"
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            FixtureCaptureService.shared.hostFilter = field.stringValue
        }
    }

    @objc func revealFolder(_ sender: Any?) {
        guard let destination = FixtureCaptureService.shared.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let service = FixtureCaptureService.shared
        switch Tag(rawValue: menuItem.tag) {
        case .toggleRecording:
            menuItem.title = service.isRecording
                ? "Stop Recording".localized + captureCountSuffix(service.writtenCount)
                : "Start Recording".localized
            return true
        case .revealFolder:
            menuItem.title = service.destination.map {
                "Reveal".localized + " “\($0.lastPathComponent)”"
            } ?? "Reveal Capture Folder".localized
            return service.destination != nil
        case .chooseFolder, .hostFilter:
            return !service.isRecording
        case .none:
            return true
        }
    }

    private func captureCountSuffix(_ count: Int) -> String {
        count == 0 ? "" : " (\(count))"
    }
}
