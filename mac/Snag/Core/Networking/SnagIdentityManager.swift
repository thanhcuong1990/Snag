import Foundation
import Network
import Security

class SnagIdentityManager {
    static let shared = SnagIdentityManager()

    private let identityFilename = "snag_identity.p12"
    private let password = "snag"

    // Kept alive for the app's lifetime — SecIdentity is backed by this keychain
    private var tempKeychain: SecKeychain?
    private var tempKeychainPath: String?

    private init() {}

    deinit {
        if let kc = tempKeychain { SecKeychainDelete(kc) }
        if let path = tempKeychainPath { try? FileManager.default.removeItem(atPath: path) }
    }

    func getIdentity() -> sec_identity_t? {
        if let identity = importFromP12() {
            return sec_identity_create(identity)
        }
        if generateIdentity(), let identity = importFromP12() {
            return sec_identity_create(identity)
        }
        return nil
    }

    // MARK: - Private

    private func importFromP12() -> SecIdentity? {
        guard let dir = getApplicationSupportDirectory() else { return nil }
        let p12URL = dir.appendingPathComponent(identityFilename)
        guard FileManager.default.fileExists(atPath: p12URL.path),
              let p12Data = try? Data(contentsOf: p12URL) else { return nil }

        guard let keychain = privateTempKeychain() else { return nil }

        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportExportKeychain as String: keychain
        ]

        var items: CFArray?
        guard SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let arr = items as? [[String: Any]],
              let first = arr.first,
              let identity = first[kSecImportItemIdentity as String] as! SecIdentity? else { return nil }

        return identity
    }

    private func privateTempKeychain() -> SecKeychain? {
        if let existing = tempKeychain { return existing }

        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("snag_\(UUID().uuidString).keychain")
        var keychain: SecKeychain?
        guard SecKeychainCreate(path, UInt32(password.count), password, false, nil, &keychain) == errSecSuccess,
              let kc = keychain else { return nil }

        // Prevent auto-lock so Network.framework's out-of-process TLS signer
        // never triggers an "Enter the keychain password" prompt.
        var settings = SecKeychainSettings(
            version: UInt32(SEC_KEYCHAIN_SETTINGS_VERS1),
            lockOnSleep: false,
            useLockInterval: false,
            lockInterval: UInt32.max
        )
        SecKeychainSetSettings(kc, &settings)
        SecKeychainUnlock(kc, UInt32(password.count), password, true)

        tempKeychain = kc
        tempKeychainPath = path
        return kc
    }

    private func getApplicationSupportDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let snagDir = appSupport.appendingPathComponent("Snag", isDirectory: true)
        if !FileManager.default.fileExists(atPath: snagDir.path) {
            try? FileManager.default.createDirectory(at: snagDir, withIntermediateDirectories: true)
        }
        return snagDir
    }

    private func generateIdentity() -> Bool {
        guard let dir = getApplicationSupportDirectory() else { return false }

        let keyPath = dir.appendingPathComponent("snag.key").path
        let certPath = dir.appendingPathComponent("snag.crt").path
        let p12Path = dir.appendingPathComponent(identityFilename).path

        let commonName = "Snag Local Network Debugger"
        let genCmd = "openssl req -x509 -newkey rsa:2048 -keyout \"\(keyPath)\" -out \"\(certPath)\" -days 3650 -nodes -subj \"/CN=\(commonName)\""
        if !runCommand(genCmd) { return false }

        let exportCmd = "openssl pkcs12 -export -out \"\(p12Path)\" -inkey \"\(keyPath)\" -in \"\(certPath)\" -password pass:\(password)"
        if !runCommand(exportCmd) { return false }

        try? FileManager.default.removeItem(atPath: keyPath)
        try? FileManager.default.removeItem(atPath: certPath)
        return true
    }

    private func runCommand(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", command]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("SnagIdentityManager: Command failed: \(command) error: \(error)")
            return false
        }
    }
}
