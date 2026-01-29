import XCTest
@testable import Snag

class SnagTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    func testCrossPlatformGoldenVectors() throws {
        // Shared Golden Values
        let pin = "MySecretPin123!"
        let saltHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        
        // Convert hex to Data helper
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
        let key = SnagCrypto.deriveKey(pin: pin, salt: salt)
        let keyHex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        
        // Key (Standard Verified): 7531498fa22ed53d8211b73d8b92b5fc98d209c0a3eefbadfba61352f7660aea
        let expectedKeyHex = "7531498fa22ed53d8211b73d8b92b5fc98d209c0a3eefbadfba61352f7660aea"
        XCTAssertEqual(keyHex, expectedKeyHex, "Key derivation mismatch! Mac and Android must agree.")
    }
    
}
