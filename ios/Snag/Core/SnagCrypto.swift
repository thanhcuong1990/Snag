import Foundation
import CryptoKit
import CommonCrypto

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
    
    static func deriveKey(pin: String, salt: Data) -> SymmetricKey {
        let pinData = Data(pin.utf8)
        let keyData = PBKDF2.deriveKey(password: pinData, salt: salt, iterations: 10000, keyByteCount: keySize)
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Encryption
    
    static func encrypt(data: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        let ciphertext = sealedBox.ciphertext + sealedBox.tag
        return (ciphertext, Data(nonce))
    }
    
    // MARK: - Decryption
    
    static func decrypt(ciphertext: Data, nonce: Data, key: SymmetricKey) throws -> Data {
        guard let nonceObj = try? AES.GCM.Nonce(data: nonce) else {
            throw SnagCryptoError.decryptionFailed
        }
        
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
        return Data()
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
