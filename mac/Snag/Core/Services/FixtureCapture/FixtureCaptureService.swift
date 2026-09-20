import Combine
import Foundation

/// Mirrors captured traffic to a folder as one response body per call, so a
/// tool outside Snag can consume it without going through the UI.
///
/// The body is written as the exact bytes the server sent. Callers downstream
/// treat a capture as evidence, and re-encoding it would lose duplicate keys
/// and number formatting that a strict decoder is sensitive to.
@MainActor
final class FixtureCaptureService: ObservableObject {

    static let shared = FixtureCaptureService()

    @Published private(set) var isRecording = false
    @Published private(set) var writtenCount = 0
    @Published private(set) var lastError: String?
    @Published var destination: URL? {
        didSet { UserDefaults.standard.set(destination?.path, forKey: Self.destinationKey) }
    }
    @Published var hostFilter: String = "" {
        didSet { UserDefaults.standard.set(hostFilter, forKey: Self.hostFilterKey) }
    }
    @Published var selectedDeviceOnly: Bool = false {
        didSet { UserDefaults.standard.set(selectedDeviceOnly, forKey: Self.selectedDeviceOnlyKey) }
    }

    private static let destinationKey = "fixtureCapture.destination"
    private static let hostFilterKey = "fixtureCapture.hostFilter"
    private static let selectedDeviceOnlyKey = "fixtureCapture.selectedDeviceOnly"
    private var seenPacketIds = Set<String>()
    private var sequence = 0

    private init() {
        if let path = UserDefaults.standard.string(forKey: Self.destinationKey) {
            destination = URL(fileURLWithPath: path)
        }
        hostFilter = UserDefaults.standard.string(forKey: Self.hostFilterKey) ?? ""
        selectedDeviceOnly = UserDefaults.standard.bool(forKey: Self.selectedDeviceOnlyKey)
    }

    /// Device the next capture is scoped to, or nil when every device is recorded.
    var targetDevice: SnagDeviceController? {
        guard selectedDeviceOnly else { return nil }
        return SnagController.shared.selectedProjectController?.selectedDeviceController
    }

    func start() {
        guard destination != nil else {
            lastError = "Choose a folder before recording."
            return
        }
        seenPacketIds.removeAll()
        sequence = 0
        writtenCount = 0
        lastError = nil
        isRecording = true
    }

    func stop() {
        isRecording = false
    }

    /// Called for every packet the publisher surfaces; ignores anything without
    /// a completed response so a fixture always reflects a finished call.
    func record(_ packet: SnagPacket) {
        guard isRecording, let destination else { return }
        guard matchesSelectedDevice(packet) else { return }
        guard let info = packet.requestInfo,
              let url = info.url,
              let encoded = info.responseData,
              let body = Data(base64Encoded: encoded),
              !body.isEmpty
        else { return }
        guard matchesHostFilter(url) else { return }

        let identity = packet.packetId ?? packet.id
        guard seenPacketIds.insert(identity).inserted else { return }

        sequence += 1
        let stem = String(format: "%04d-%@", sequence, slug(for: url))
        do {
            try body.write(to: destination.appendingPathComponent("\(stem).json"))
            try sidecar(for: info, body: body)
                .write(to: destination.appendingPathComponent("\(stem).meta.json"))
            writtenCount += 1
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func matchesSelectedDevice(_ packet: SnagPacket) -> Bool {
        guard selectedDeviceOnly else { return true }
        guard let target = targetDevice?.deviceId?.lowercased() else { return false }
        let deviceId = (packet.device?.deviceId ?? packet.control?.deviceId)?.lowercased()
        return deviceId == target
    }

    private func matchesHostFilter(_ url: String) -> Bool {
        let needle = hostFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return url.localizedCaseInsensitiveContains(needle)
    }

    private func slug(for url: String) -> String {
        let path = URLComponents(string: url)?.path ?? url
        let cleaned = path
            .split(separator: "/")
            .suffix(2)
            .joined(separator: "-")
            .replacingOccurrences(of: "[^A-Za-z0-9-]", with: "", options: .regularExpression)
        return cleaned.isEmpty ? "capture" : String(cleaned.prefix(48))
    }

    private func sidecar(for info: SnagRequestInfo, body: Data) throws -> Data {
        var payload: [String: Any] = [
            "url": info.url ?? "",
            "requestMethod": info.requestMethod?.rawValue.uppercased() ?? "GET",
            "statusCode": info.statusCode ?? "",
            "responseEncoding": "utf8",
            "responseByteCount": body.count,
            "capturedAt": ISO8601DateFormatter().string(from: info.endDate ?? Date()),
        ]
        if let headers = info.responseHeaders {
            payload["responseHeaders"] = headers
        }
        if let encodedRequest = info.requestBody,
           let requestBody = Data(base64Encoded: encodedRequest),
           let text = String(data: requestBody, encoding: .utf8) {
            payload["requestBody"] = text
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
