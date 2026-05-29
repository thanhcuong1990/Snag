import Foundation
import Network
import Security

class SnagIdentityManager {
    static let shared = SnagIdentityManager()

    private let identityFilename = "snag_identity.p12"
    private let keychainFilename = "snag_identity.keychain"
    private let password = "snag"

    private var snagKeychain: SecKeychain?
    private var snagKeychainPath: String?

    private init() {}

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

        guard let keychain = persistentKeychain(in: dir), let kcPath = snagKeychainPath else { return nil }

        var options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportExportKeychain as String: keychain
        ]
        // Trust every application to use the imported key without prompting.
        // The released app is ad-hoc signed (no Developer ID), so it has no
        // stable Team ID to authorize via the partition list and its cdhash
        // changes every build — an allow-all ACL is the only identity-independent
        // way to suppress the keychain prompt. Safe here: this is a locally
        // generated, self-signed cert for the local network debugger, not a
        // real credential.
        if let access = makeAllowAllAccess() {
            options[kSecImportExportAccess as String] = access
        }

        var items: CFArray?
        let importStatus = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        // errSecDuplicateItem is fine — the identity is already in our
        // persistent keychain from a previous launch. Look it up below.
        guard importStatus == errSecSuccess || importStatus == errSecDuplicateItem else { return nil }

        if importStatus == errSecSuccess {
            // Fresh import — set partition list so out-of-process Apple
            // system processes (securityd / trustd / networkd's TLS signer)
            // can use the key without prompting. Modern macOS gate; legacy
            // ACLs are insufficient on their own. Only needed once; on
            // subsequent launches the import returns errSecDuplicateItem
            // and the partition list is already in place.
            setPartitionList(keychainPath: kcPath)

            if let arr = items as? [[String: Any]],
               let first = arr.first,
               let identityRef = first[kSecImportItemIdentity as String] {
                return (identityRef as! SecIdentity)
            }
        }

        // Duplicate, or import returned an empty result — look up the
        // identity already in the keychain.
        return lookupIdentityInKeychain(keychain)
    }

    private func lookupIdentityInKeychain(_ keychain: SecKeychain) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchSearchList as String: [keychain],
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result else { return nil }
        return (item as! SecIdentity)
    }

    private func makeAllowAllAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate("Snag Local Network Debugger" as CFString, [] as CFArray, &access) == errSecSuccess,
              let acc = access else { return nil }

        var aclList: CFArray?
        guard SecAccessCopyACLList(acc, &aclList) == errSecSuccess,
              let acls = aclList as? [SecACL] else { return acc }

        for acl in acls {
            var apps: CFArray?
            var desc: CFString?
            var prompt = SecKeychainPromptSelector(rawValue: 0)
            SecACLCopyContents(acl, &apps, &desc, &prompt)
            // A nil application list means any application may use the key
            // without prompting — the in-code equivalent of `security import -A`.
            SecACLSetContents(acl, nil, (desc ?? "" as CFString), prompt)
        }
        return acc
    }

    private func setPartitionList(keychainPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "set-key-partition-list",
            "-S", "apple-tool:,apple:",
            "-s",
            "-k", password,
            keychainPath
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("SnagIdentityManager: set-key-partition-list failed: \(error)")
        }
    }

    private func persistentKeychain(in dir: URL) -> SecKeychain? {
        if let existing = snagKeychain { return existing }

        let path = dir.appendingPathComponent(keychainFilename).path
        var keychain: SecKeychain?

        if FileManager.default.fileExists(atPath: path) {
            if SecKeychainOpen(path, &keychain) == errSecSuccess, let kc = keychain {
                let unlockStatus = SecKeychainUnlock(kc, UInt32(password.utf8.count), password, true)
                if unlockStatus == errSecSuccess {
                    disableAutoLock(keychainPath: path)
                    removeFromSearchList(path: path)
                    snagKeychain = kc
                    snagKeychainPath = path
                    return kc
                }
                // Wrong password — likely a stale keychain from an earlier
                // build. Drop it and recreate below.
            }
            try? FileManager.default.removeItem(atPath: path)
            keychain = nil
        }

        guard SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychain) == errSecSuccess,
              let kc = keychain else { return nil }

        SecKeychainUnlock(kc, UInt32(password.utf8.count), password, true)
        disableAutoLock(keychainPath: path)

        // Pull the keychain back out of the user's default search list so
        // securityd / trustd don't scan it during TLS handshake (which would
        // surface an "Enter the keychain password" prompt).
        removeFromSearchList(path: path)

        snagKeychain = kc
        snagKeychainPath = path
        return kc
    }

    // Make the keychain never auto-lock. A freshly created keychain defaults to
    // lock-on-sleep with a 300s idle timeout, and the in-process
    // SecKeychainSetSettings call does not reliably override that default — so
    // the keychain relocks behind the app's back and the next TLS handshake
    // surfaces an "Enter the keychain password" prompt. `security
    // set-keychain-settings` with no flags clears both the timeout and
    // lock-on-sleep; run it on every launch so keychains created before this
    // fix get repaired too.
    private func disableAutoLock(keychainPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["set-keychain-settings", keychainPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("SnagIdentityManager: set-keychain-settings failed: \(error)")
        }
    }

    private func removeFromSearchList(path: String) {
        var searchList: CFArray?
        guard SecKeychainCopySearchList(&searchList) == errSecSuccess,
              let list = searchList as? [SecKeychain] else { return }

        let filtered = list.filter { kc in
            var buf = [CChar](repeating: 0, count: 1024)
            var len = UInt32(buf.count)
            guard SecKeychainGetPath(kc, &len, &buf) == errSecSuccess else { return true }
            return String(cString: buf) != path
        }

        if filtered.count != list.count {
            SecKeychainSetSearchList(filtered as CFArray)
        }
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
