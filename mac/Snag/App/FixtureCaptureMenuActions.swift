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
        case selectedDeviceOnly = 8104
    }

    @objc func toggleSelectedDeviceOnly(_ sender: Any?) {
        FixtureCaptureService.shared.selectedDeviceOnly.toggle()
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
        alert.layout()
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            FixtureCaptureService.shared.hostFilter = field.stringValue
        }
    }

    @objc func revealFolder(_ sender: Any?) {
        guard let destination = FixtureCaptureService.shared.activeDestination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let service = FixtureCaptureService.shared
        switch Tag(rawValue: menuItem.tag) {
        case .toggleRecording:
            if let session = service.session {
                menuItem.title = "Stop Recording".localized + captureCountSuffix(service.writtenCount)
                    + scriptedScopeSuffix(session.scope)
            } else {
                menuItem.title = service.isRecording
                    ? "Stop Recording".localized + captureCountSuffix(service.writtenCount)
                    : "Start Recording".localized
            }
            return true
        case .revealFolder:
            menuItem.title = service.activeDestination.map {
                "Reveal".localized + " “\($0.lastPathComponent)”"
            } ?? "Reveal Capture Folder".localized
            return service.activeDestination != nil
        case .selectedDeviceOnly:
            // A scripted session carries its own scope and ignores this setting.
            if let session = service.session {
                menuItem.state = .off
                menuItem.title = "Record Selected Device Only".localized + scriptedScopeSuffix(session.scope)
                return false
            }
            menuItem.state = service.selectedDeviceOnly ? .on : .off
            menuItem.title = service.selectedDeviceOnly
                ? "Record Selected Device Only".localized + targetDeviceSuffix(service.targetDevice)
                : "Record Selected Device Only".localized
            return true
        case .hostFilter:
            menuItem.title = service.hostFilter.isEmpty
                ? "Host Filter…".localized
                : "Host Filter…".localized + " (\(service.hostFilter))"
            return !service.isRecording
        case .chooseFolder:
            return !service.isRecording
        case .none:
            return true
        }
    }

    private func captureCountSuffix(_ count: Int) -> String {
        count == 0 ? "" : " (\(count))"
    }

    private func scriptedScopeSuffix(_ scope: CaptureScope) -> String {
        let parts = [scope.device, scope.bundleId].filter { !$0.isEmpty }
        let scopeText = parts.isEmpty ? "Every Device".localized : parts.joined(separator: ", ")
        return " — " + "Scripted".localized + ": \(scopeText)"
    }

    private func targetDeviceSuffix(_ device: SnagDeviceController?) -> String {
        guard let name = device?.deviceName, !name.isEmpty else {
            return " — " + "No Device Selected".localized
        }
        return " — \(name)"
    }
}
