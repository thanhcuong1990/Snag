import Foundation

/// Identity of the Mac this copy of Snag runs on.
enum LocalMachine {

    static let name: String = {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        return String(cString: buffer)
    }()

    /// Whether a device is hosted by a different Mac.
    static func isRemote(_ hostMachine: String?) -> Bool {
        guard let key = comparisonKey(hostMachine) else { return false }
        return key != comparisonKey(name)
    }

    /// Device list label naming the hosting Mac.
    static func label(for hostMachine: String?) -> String? {
        guard let display = displayName(hostMachine) else { return nil }
        return isRemote(hostMachine) ? display : "This Mac".localized
    }

    /// Host machine name without the ".local" suffix.
    static func displayName(_ hostMachine: String?) -> String? {
        guard let value = hostMachine?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value.hasSuffix(".local") ? String(value.dropLast(".local".count)) : value
    }

    private static func comparisonKey(_ hostMachine: String?) -> String? {
        displayName(hostMachine)?.lowercased()
    }
}
