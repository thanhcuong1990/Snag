import XCTest
@testable import Snag
import CryptoKit

class SnagCryptoTests: XCTestCase {

    func testDeriveKey() {
        let pin = "123456"
        let salt = SnagCrypto.randomSalt()
        
        let key1 = SnagCrypto.deriveKey(pin: pin, salt: salt)
        let key2 = SnagCrypto.deriveKey(pin: pin, salt: salt)
        
        XCTAssertEqual(key1.withUnsafeBytes { Data($0) }, key2.withUnsafeBytes { Data($0) }, "Key derivation should be deterministic")
        
        let differentSalt = SnagCrypto.randomSalt()
        let key3 = SnagCrypto.deriveKey(pin: pin, salt: differentSalt)
        XCTAssertNotEqual(key1.withUnsafeBytes { Data($0) }, key3.withUnsafeBytes { Data($0) }, "Different salt should produce different key")
        
        let differentPin = "654321"
        let key4 = SnagCrypto.deriveKey(pin: differentPin, salt: salt)
        XCTAssertNotEqual(key1.withUnsafeBytes { Data($0) }, key4.withUnsafeBytes { Data($0) }, "Different PIN should produce different key")
    }

    func testEncryptionDecryption() throws {
        let pin = "1234"
        let salt = SnagCrypto.randomSalt()
        let key = SnagCrypto.deriveKey(pin: pin, salt: salt)
        
        let plaintext = "Hello World! This is a secure message.".data(using: .utf8)!
        
        let (ciphertext, nonce) = try SnagCrypto.encrypt(data: plaintext, key: key)
        
        XCTAssertNotEqual(plaintext, ciphertext, "Ciphertext should not match plaintext")
        
        let decrypted = try SnagCrypto.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)
        
        XCTAssertEqual(plaintext, decrypted, "Decrypted data should match original plaintext")
    }
    
    func testDecryptionFailureWithWrongKey() throws {
        let pin = "1234"
        let salt = SnagCrypto.randomSalt()
        let key = SnagCrypto.deriveKey(pin: pin, salt: salt)
        
        let plaintext = "Secret".data(using: .utf8)!
        let (ciphertext, nonce) = try SnagCrypto.encrypt(data: plaintext, key: key)
        
        // Wrong Key
        let wrongKey = SnagCrypto.deriveKey(pin: "Wrong", salt: salt)
        
        XCTAssertThrowsError(try SnagCrypto.decrypt(ciphertext: ciphertext, nonce: nonce, key: wrongKey)) { error in
            // CryptoKit usually throws AES.GCM.AuthenticationFailure or similar
            // Our wrapper throws internal errors or propagates CK errors.
        }
    }
    
    func testRandomSaltUniqueness() {
        let s1 = SnagCrypto.randomSalt()
        let s2 = SnagCrypto.randomSalt()
        XCTAssertNotEqual(s1, s2)
        XCTAssertEqual(s1.count, 32)
    }
}
