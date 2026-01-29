import Foundation
import CryptoKit

enum SnagCryptoError: Error {
    case invalidKey
    case encryptionFailed
    case decryptionFailed
}

class SnagCrypto {
    
    // MARK: - Constants
    private static let saltSize = 32
    private static let nonceSize = 12
    private static let keySize = 32 // AES-256
    
    // MARK: - Key Derivation
    
    /// Derives a symmetric key from the PIN and Salt using PBKDF2 (HMAC-SHA256).
    /// - Parameters:
    ///   - pin: The user-supplied PIN.
    ///   - salt: The server-provided salt (hex string or raw bytes).
    /// - Returns: A SymmetricKey for AES-GCM.
    static func deriveKey(pin: String, salt: Data) -> SymmetricKey {
        // Use PBKDF2 with a reasonable iteration count for interactive auth
        let pinData = Data(pin.utf8)
        // 10,000 rounds is a baseline; for mobile/desktop interactive limits this is safe.
        // Snag is a local tool, extreme KDF hardness isn't the primary goal vs UX, but we want to prevent trivial brute force.
        let keyData = PBKDF2.deriveKey(password: pinData, salt: salt, iterations: 10000, keyByteCount: keySize)
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Encryption
    
    /// Encrypts data using AES-GCM.
    /// - Parameters:
    ///   - data: The plaintext data.
    ///   - key: The symmetric key.
    /// - Returns: A tuple containing the ciphertext (including tag) and the nonce.
    static func encrypt(data: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        // sealedBox.combined includes the nonce, ciphertext, and tag.
        // However, we want to return the nonce separately if our protocol dictates sending it as a separate field,
        // OR we can just return sealedBox.combined and let the receiver pull it apart.
        // For simplicity in JSON protocols, splitting them is often clearer.
        // But `combined` is standard. Let's return separate components for flexibility in the JSON model.
        
        let ciphertext = sealedBox.ciphertext + sealedBox.tag
        return (ciphertext, Data(nonce))
    }
    
    // MARK: - Decryption
    
    /// Decrypts data using AES-GCM.
    /// - Parameters:
    ///   - ciphertext: The encrypted data (ciphertext + tag).
    ///   - nonce: The nonce used for encryption.
    ///   - key: The symmetric key.
    /// - Returns: The decrypted plaintext data.
    static func decrypt(ciphertext: Data, nonce: Data, key: SymmetricKey) throws -> Data {
        guard let nonceObj = try? AES.GCM.Nonce(data: nonce) else {
            throw SnagCryptoError.decryptionFailed
        }
        
        // let sealedBox = try AES.GCM.SealedBox(nonce: nonceObj, ciphertext: ciphertext, tag: Data()) // Init using raw parts is tricky in CryptoKit without the specific constructor or combined data.
        // Actually, it's easier to reconstruct the "combined" data if we have the standard format,
        // or use `try AES.GCM.open(sealedBox, using: key)`
        
        // Let's use the combined data approach if possible, or construct SealedBox properly.
        // CryptoKit's `SealedBox(nonce:ciphertext:tag:)` is available.
        // But `ciphertext` param in our function signature implies it might contain the tag if we used `ciphertextWithTag` property during encryption.
        // AES.GCM.SealedBox.ciphertextWithTag is: (ciphertext + tag).
        
        // If we passed `sealedBox.ciphertext` + `sealedBox.tag` separately it would be clearer.
        // But `ciphertextWithTag` is a convenient blob.
        // There isn't a direct initializer for `ciphertextWithTag` + `nonce` in standard CryptoKit public API immediately.
        // We might need to split it manually if we don't use `combined`.
        
        // Alternative: Use `APP_LAYER_COMBINED` format: Nonce (12) + Ciphertext + Tag.
        // That is `sealedBox.combined`.
        
        // Let's try to stick to `sealedBox.combined` for transport if possible? 
        // But our plan said specific fields.
        
        // Let's implement helper to open `ciphertextWithTag`.
        // The Tag is usually 16 bytes at the end.
        let tagSize = 16
        guard ciphertext.count > tagSize else { throw SnagCryptoError.decryptionFailed }
        
        let actualCiphertext = ciphertext.prefix(ciphertext.count - tagSize)
        let tag = ciphertext.suffix(tagSize)
        
        let box = try AES.GCM.SealedBox(nonce: nonceObj, ciphertext: actualCiphertext, tag: tag)
        return try AES.GCM.open(box, using: key)
    }
    
    // MARK: - Utilities
    
    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltSize, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data() // Should not happen
    }
    
    static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonceSize, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data()
    }
}

// Minimal PBKDF2 implementation wrapper since CryptoKit doesn't expose it directly in a simple way in older versions or purely via CryptoKit.
// Wait, CryptoKit DOES NOT have PBKDF2. CommonCrypto does (CCKeyDerivation).
// We should use CommonCrypto for KDF.

import CommonCrypto

class PBKDF2 {
    static func deriveKey(password: Data, salt: Data, iterations: Int, keyByteCount: Int) -> Data {
        var derivedKey = Data(repeating: 0, count: keyByteCount)
        
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }
        
        if status == kCCSuccess {
            return derivedKey
        } else {
            print("PBKDF2 Error: \(status)")
            return Data()
        }
    }
}
