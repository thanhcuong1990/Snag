import Cocoa

/// Menu commands controlling what the device sidebar shows.
@MainActor
final class ViewMenuActions: NSObject, NSMenuItemValidation {

    static let shared = ViewMenuActions()

    enum Tag: Int {
        case onlyLocalDevices = 8200
    }

    @objc func toggleOnlyLocalDevices(_ sender: Any?) {
        SettingsManager.shared.showOnlyLocalDevices.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch Tag(rawValue: menuItem.tag) {
        case .onlyLocalDevices:
            menuItem.state = SettingsManager.shared.showOnlyLocalDevices ? .on : .off
            menuItem.title = "Only Devices on This Mac".localized + machineSuffix()
            return true
        case .none:
            return true
        }
    }

    private func machineSuffix() -> String {
        guard let name = LocalMachine.displayName(LocalMachine.name) else { return "" }
        return " (\(name))"
    }
}
