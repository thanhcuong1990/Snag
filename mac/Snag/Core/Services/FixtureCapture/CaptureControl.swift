import AppKit
import Combine
import Foundation

/// Executes `snag://capture` URL commands and writes the recording state to a status file.
@MainActor
final class CaptureControl {

    static let shared = CaptureControl()

    nonisolated static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Snag", isDirectory: true)
    }

    nonisolated static var statusFileURL: URL {
        supportDirectory.appendingPathComponent("capture-status.json")
    }

    private let service = FixtureCaptureService.shared
    private var lastRequestId: String?
    private var commandError: String?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Publishers.CombineLatest4(service.$isRecording, service.$writtenCount, service.$lastError, service.$session)
            .dropFirst()
            // Every captured response moves writtenCount, and the file carries the
            // whole device list, so rewriting it per packet would be the costliest
            // part of a busy recording. Commands write immediately in handle(_:).
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.writeStatus() }
            }
            .store(in: &cancellables)
    }

    /// Creates the token a caller needs and records the state of a fresh launch.
    func prepare() {
        CaptureToken.ensure()
        writeStatus()
    }

    func handle(_ url: URL) {
        switch CaptureCommand.parse(url) {
        case .failure(let error):
            lastRequestId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "req" }?.value
            commandError = error.localizedDescription
        case .success(let envelope):
            lastRequestId = envelope.requestId
            if CaptureToken.matches(envelope.token) {
                commandError = nil
                run(envelope.command)
            } else {
                commandError = "Unauthorized: this command carried no valid capture token."
                    + " The token is in \(CaptureToken.fileURL.path)."
            }
        }
        writeStatus()
    }

    private func run(_ command: CaptureCommand) {
        switch command {
        case .start(let options):
            do {
                try service.start(options)
            } catch {
                commandError = error.localizedDescription
            }
        case .stop:
            service.stop()
        case .status:
            break
        }
    }

    func writeStatus() {
        // A scripted recording opens no window and leaves the menu untouched, so
        // the dock tile is the only sign that Snag is writing traffic to disk.
        NSApp.dockTile.badgeLabel = service.session != nil ? "REC" : nil

        var devices: [[String: Any]] = []
        for project in SnagController.shared.projectControllers {
            for device in project.deviceControllers {
                let entry: [String: String] = [
                    "id": device.deviceId ?? "",
                    "name": device.deviceName ?? "",
                    "project": project.projectName ?? "",
                    "bundleId": project.bundleId ?? "",
                ]
                devices.append(entry)
            }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let status: [String: Any] = [
            "recording": service.isRecording,
            "scripted": service.session != nil,
            "destination": service.activeDestination?.path ?? "",
            "lastRecordingFolder": service.lastRecordingFolder?.path ?? "",
            "hostFilter": service.activeHostFilter,
            "device": service.session?.scope.device ?? "",
            "bundleId": service.session?.scope.bundleId ?? "",
            "selectedDeviceOnly": service.session == nil && service.selectedDeviceOnly,
            "writtenCount": service.writtenCount,
            "lastError": service.lastError ?? "",
            "commandError": commandError ?? "",
            "lastRequestId": lastRequestId ?? "",
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": info["CFBundleVersion"] as? String ?? "",
            "appPath": Bundle.main.bundlePath,
            "devices": devices,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        do {
            let file = Self.statusFileURL
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("Snag: cannot write capture status: \(error.localizedDescription)")
        }
    }
}
