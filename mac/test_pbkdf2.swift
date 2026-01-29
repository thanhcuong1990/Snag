import Foundation
import CommonCrypto

// PBKDF2 Helper
func deriveKey(password: Data, salt: Data, iterations: Int, keyByteCount: Int) -> Data {
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

// Input
let pin = "MySecretPin123!"
let saltHex = "c0122cd33f7e07d7a91ac0af9be52a602f97c2c54b20b85bc3ef1eeaaaf56cea"

// Hex to Data
func dataFromHex(_ hex: String) -> Data {
    var data = Data()
    var hexStr = hex
    while hexStr.count > 0 {
        let c = String(hexStr.prefix(2))
        hexStr = String(hexStr.dropFirst(2))
        if let b = UInt8(c, radix: 16) {
            data.append(b)
        }
    }
    return data
}

let salt = dataFromHex(saltHex)
let pinData = Data(pin.utf8)

// Derive Key
let key = deriveKey(password: pinData, salt: salt, iterations: 100000, keyByteCount: 32)
let keyHex = key.map { String(format: "%02x", $0) }.joined()

print("Mac Key: \(keyHex)")
print("Expected Key: bc8c73586444b223677470c67158daeeb73474cf48eea76f75dc597b16804d89")
print("Match: \(keyHex == "bc8c73586444b223677470c67158daeeb73474cf48eea76f75dc597b16804d89")")

// Hash
var dataToHash = key
dataToHash.append(Data("Client".utf8))
var hashBytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
dataToHash.withUnsafeBytes { ptr in
    _ = CC_SHA256(ptr.baseAddress, CC_LONG(dataToHash.count), &hashBytes)
}
let hashHex = hashBytes.map { String(format: "%02x", $0) }.joined()

print("Mac Hash: \(hashHex)")
print("Expected Hash: 42ee901480140b6a9dd656d06977a13697d158db035816714c0c501a30e7de4f")
print("Hash Match: \(hashHex == "42ee901480140b6a9dd656d06977a13697d158db035816714c0c501a30e7de4f")")
