import Foundation

/// A fixture-capture command received through the `snag://capture/…` URL scheme.
enum CaptureCommand: Equatable {
    case start(CaptureStartOptions)
    case stop
    case status

    /// A parsed command plus the caller's request id, echoed in the status file.
    struct Envelope: Equatable {
        let command: CaptureCommand
        let requestId: String?
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case notACaptureURL
        case unknownAction(String)
        case missingFolder

        var errorDescription: String? {
            switch self {
            case .notACaptureURL: return "Not a snag://capture URL."
            case .unknownAction(let action): return "Unknown capture action “\(action)”."
            case .missingFolder: return "start needs a folder."
            }
        }
    }

    static func parse(_ url: URL) -> Result<Envelope, ParseError> {
        guard url.scheme?.lowercased() == "snag", url.host?.lowercased() == "capture" else {
            return .failure(.notACaptureURL)
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let requestId = value("req").isEmpty ? nil : value("req")
        let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        switch action {
        case "start":
            let folder = value("folder")
            guard !folder.isEmpty else { return .failure(.missingFolder) }
            let options = CaptureStartOptions(
                folder: (folder as NSString).expandingTildeInPath,
                hostFilter: value("host"),
                scope: CaptureScope(device: value("device"), bundleId: value("bundle")),
                append: ["1", "true", "yes"].contains(value("append").lowercased())
            )
            return .success(Envelope(command: .start(options), requestId: requestId))
        case "stop":
            return .success(Envelope(command: .stop, requestId: requestId))
        case "status":
            return .success(Envelope(command: .status, requestId: requestId))
        default:
            return .failure(.unknownAction(action))
        }
    }
}

struct CaptureStartOptions: Equatable {
    let folder: String
    let hostFilter: String
    let scope: CaptureScope
    let append: Bool
}

/// Limits a recording to one device and/or one app bundle id.
struct CaptureScope: Equatable {
    var device: String = ""
    var bundleId: String = ""

    static let everything = CaptureScope()

    var isEmpty: Bool { device.isEmpty && bundleId.isEmpty }

    /// Matches the device id or name, and the bundle id, exactly and ignoring case.
    func matches(deviceId: String?, deviceName: String?, bundleId packetBundleId: String?) -> Bool {
        if !device.isEmpty {
            let candidates = [deviceId, deviceName].compactMap { $0 }
            guard candidates.contains(where: { $0.caseInsensitiveCompare(device) == .orderedSame }) else {
                return false
            }
        }
        if !bundleId.isEmpty {
            guard let packetBundleId, packetBundleId.caseInsensitiveCompare(bundleId) == .orderedSame else {
                return false
            }
        }
        return true
    }
}

enum CaptureFolder {

    /// The highest `NNNN-` file prefix in the folder, or 0 when there is none.
    static func highestSequence(in folder: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name -> Int? in
            guard name.count > 5, name[name.index(name.startIndex, offsetBy: 4)] == "-" else { return nil }
            return Int(name.prefix(4))
        }.max() ?? 0
    }

    /// Whether the folder holds anything besides hidden files such as `.DS_Store`.
    static func hasVisibleContents(_ folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { !$0.hasPrefix(".") }
    }
}
