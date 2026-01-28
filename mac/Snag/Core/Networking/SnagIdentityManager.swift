import Foundation
import Network
import Security

class SnagIdentityManager {
    static let shared = SnagIdentityManager()
    
    private let identityFilename = "snag_identity.p12"
    private let password = "snag"
    
    private init() {}
    
    func getIdentity() -> sec_identity_t? {
        if let identity = loadExistingIdentity() {
            return identity
        }
        
        if generateIdentity() {
            return loadExistingIdentity()
        }
        
        return nil
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
    
    private func loadExistingIdentity() -> sec_identity_t? {
        guard let dir = getApplicationSupportDirectory() else { return nil }
        let p12URL = dir.appendingPathComponent(identityFilename)
        
        guard FileManager.default.fileExists(atPath: p12URL.path) else { return nil }
        
        do {
            let p12Data = try Data(contentsOf: p12URL)
            let options: [String: Any] = [
                kSecImportExportPassphrase as String: password
            ]
            
            var items: CFArray?
            let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
            
            if status == errSecSuccess, let items = items as? [[String: Any]], let firstItem = items.first {
                if let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity? {
                    return sec_identity_create(identity)
                }
            }
        } catch {
            print("SnagIdentityManager: Failed to load .p12: \(error)")
        }
        
        return nil
    }
    
    private func generateIdentity() -> Bool {
        guard let dir = getApplicationSupportDirectory() else { return false }
        
        let keyPath = dir.appendingPathComponent("snag.key").path
        let certPath = dir.appendingPathComponent("snag.crt").path
        let p12Path = dir.appendingPathComponent(identityFilename).path
        
        let commonName = "Snag Local Network Debugger"
        
        // 1. Generate Private Key and Self-signed Certificate
        let genCmd = "openssl req -x509 -newkey rsa:2048 -keyout \"\(keyPath)\" -out \"\(certPath)\" -days 3650 -nodes -subj \"/CN=\(commonName)\""
        if !runCommand(genCmd) { return false }
        
        // 2. Export to PKCS12
        let exportCmd = "openssl pkcs12 -export -out \"\(p12Path)\" -inkey \"\(keyPath)\" -in \"\(certPath)\" -password pass:\(password)"
        if !runCommand(exportCmd) { return false }
        
        // Cleanup temporary files
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
