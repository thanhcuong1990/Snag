package com.snag.core

import org.junit.Assert.*
import org.junit.Test

class SnagCryptoTest {

    @Test
    fun testKeyDerivation() {
        val pin = "MySecretPin123!"
        val saltHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        
        val key = SnagCrypto.deriveKey(pin, SnagCrypto.hexToBytes(saltHex))
        
        assertEquals("AES", key.algorithm)
        assertEquals(32, key.encoded.size) // 256 bits
        
        val keyHex = SnagCrypto.bytesToHex(key.encoded)
        println("ACTUAL_KEY_HEX: $keyHex")
        // Updated to confirmed Standard UTF-8 PBKDF2-HMAC-SHA256 result for this PIN/Salt
        val expectedKeyHex = "7531498fa22ed53d8211b73d8b92b5fc98d209c0a3eefbadfba61352f7660aea"
        
        assertEquals("KDF Mismatch", expectedKeyHex, keyHex) 
    }

    @Test
    fun testEncryptionDecryption() {
        val pin = "MySecretPin123!"
        val saltHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        val key = SnagCrypto.deriveKey(pin, SnagCrypto.hexToBytes(saltHex))
        
        val plaintext = "Hello Snag".toByteArray(Charsets.UTF_8)
        
        val (ciphertext, nonce) = SnagCrypto.encrypt(plaintext, key)
        
        // Decrypt
        val decrypted = SnagCrypto.decrypt(ciphertext, nonce, key)
        
        assertArrayEquals(plaintext, decrypted)
    }

    @Test
    fun testHexConversion() {
        val hex = "deadbeef"
        val bytes = SnagCrypto.hexToBytes(hex)
        val newHex = SnagCrypto.bytesToHex(bytes)
        
        assertEquals(hex, newHex)
    }
    @Test
    fun testComprehensiveGoldenVectors() {
        // 1. Setup Golden Inputs (Generated externally via Python `cryptography` lib)
        val pin = "GoldenCheck123"
        // 32 bytes of zeros
        val saltHex = "0000000000000000000000000000000000000000000000000000000000000000"
        
        // 2. Expected Outputs
        val expectedKeyHex = "fa8edeb1593dc52e6b1fe31f48f020d123828d64e8ab52a53374e78114f8b5d0"
        val expectedAuthHash = "f6314c4331d8e856d121b7d6256f9e11c30a52544b6221ec8cf00ba7c2acb71e"
        // Ciphertext for "SnagGoldenVector" with 12 bytes zero nonce
        val expectedCiphertextHex = "5aa6e08095b5895492796ad4ebdc260a4ed0e084bd52ae1b7d0e2be4567234b1"
        val nonceHex = "000000000000000000000000"
        val plaintextString = "SnagGoldenVector"
        
        // 3. Verify Key Derivation
        val salt = SnagCrypto.hexToBytes(saltHex)
        val key = SnagCrypto.deriveKey(pin, salt)
        val keyHex = SnagCrypto.bytesToHex(key.encoded)
        
        assertEquals("KDF Mismatch against Python Golden Vector", expectedKeyHex, keyHex)
        
        // 4. Verify Auth Hash (Key + "Client")
        val validationString = "Client"
        val validationBytes = validationString.toByteArray(Charsets.UTF_8)
        val keyBytes = key.encoded
        val dataToHash = keyBytes + validationBytes
        
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val hashBytes = md.digest(dataToHash)
        val computedHash = SnagCrypto.bytesToHex(hashBytes)
        
        assertEquals("Auth Hash Mismatch", expectedAuthHash, computedHash)
        
        // 5. Verify Decryption
        val ciphertext = SnagCrypto.hexToBytes(expectedCiphertextHex)
        val nonce = SnagCrypto.hexToBytes(nonceHex)
        
        val decryptedData = SnagCrypto.decrypt(ciphertext, nonce, key)
        val decryptedString = String(decryptedData, Charsets.UTF_8)
        
        assertEquals("Decryption Mismatch against Python Golden Vector", plaintextString, decryptedString)
    }
}
