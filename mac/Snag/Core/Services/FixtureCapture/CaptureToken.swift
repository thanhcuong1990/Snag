import Foundation
import Security

/// The shared secret a `snag://capture` URL has to carry.
///
/// Nothing authenticates a URL scheme: any local process, and any web page the
/// user lets through the browser's prompt, can send one. Since a capture holds
/// response bodies and headers, the token is what keeps a drive-by URL from
/// starting a silent recording — it lives in a file only the user can read.
enum CaptureToken {

    static var fileURL: URL {
        CaptureControl.supportDirectory.appendingPathComponent("capture-token")
    }

    /// The stored token, created on first use. Nil when it cannot be stored,
    /// which refuses every command rather than accepting an unauthenticated one.
    @discardableResult
    static func ensure() -> String? {
        if let stored = try? String(contentsOf: fileURL, encoding: .utf8) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let token = generate()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try token.write(to: fileURL, atomically: true, encoding: .utf8)
            // An atomic write lands a fresh file, so the mode is set afterwards.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return token
        } catch {
            NSLog("Snag: cannot store the capture token: \(error.localizedDescription)")
            return nil
        }
    }

    static func matches(_ candidate: String?) -> Bool {
        guard let candidate, !candidate.isEmpty, let token = ensure() else { return false }
        return candidate == token
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
