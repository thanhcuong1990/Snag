package com.snag.core

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

object SnagCrypto {
    private const val KEY_ALGORITHM = "AES"
    private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val TAG_LENGTH_BITS = 128
    private const val NONCE_LENGTH_BYTES = 12
    private const val PBKDF2_ITERATIONS = 100000
    private const val KEY_LENGTH_BITS = 256

    fun deriveKey(pin: String, salt: ByteArray): SecretKey {
        // Manually implement PBKDF2 to ensure UTF-8 handling of the PIN
        // and consistency across all Android devices/providers.
        val passwordBytes = pin.toByteArray(Charsets.UTF_8)
        val keyBytes = pbkdf2HmacSha256(passwordBytes, salt, PBKDF2_ITERATIONS, KEY_LENGTH_BITS / 8)
        return SecretKeySpec(keyBytes, KEY_ALGORITHM)
    }

    private fun pbkdf2HmacSha256(password: ByteArray, salt: ByteArray, iterations: Int, keyLengthBytes: Int): ByteArray {
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(password, "HmacSHA256"))
        
        val dk = ByteArray(keyLengthBytes)
        val hLen = mac.macLength // 32
        val l = (keyLengthBytes + hLen - 1) / hLen
        val r = keyLengthBytes - (l - 1) * hLen
        
        var outputOffset = 0
        
        for (i in 1..l) {
            // U1 = PRF(P, S || INT_32_BE(i))
            val intBuffer = java.nio.ByteBuffer.allocate(4).putInt(i).array()
            mac.update(salt)
            mac.update(intBuffer)
            var u = mac.doFinal() // U1
            
            // XOR sum (F function)
            val t = u.clone()
            
            for (j in 2..iterations) {
                u = mac.doFinal(u) // Uj
                for (k in u.indices) {
                    t[k] = (t[k].toInt() xor u[k].toInt()).toByte()
                }
            }
            
            val len = if (i == l) r else hLen
            System.arraycopy(t, 0, dk, outputOffset, len)
            outputOffset += hLen
        }
        return dk
    }

    /**
     * Encrypts data using AES-GCM.
     * Returns a Pair of (Ciphertext, Nonce). Both are Raw ByteArrays.
     */
    fun encrypt(data: ByteArray, key: SecretKey): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        val nonce = ByteArray(NONCE_LENGTH_BYTES).apply {
            SecureRandom().nextBytes(this)
        }
        val gcmSpec = GCMParameterSpec(TAG_LENGTH_BITS, nonce)
        cipher.init(Cipher.ENCRYPT_MODE, key, gcmSpec)

        val ciphertext = cipher.doFinal(data)
        
        return Pair(ciphertext, nonce)
    }

    /**
     * Decrypts AES-GCM data.
     */
    fun decrypt(ciphertext: ByteArray, nonce: ByteArray, key: SecretKey): ByteArray {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        val gcmSpec = GCMParameterSpec(TAG_LENGTH_BITS, nonce)
        cipher.init(Cipher.DECRYPT_MODE, key, gcmSpec)

        return cipher.doFinal(ciphertext)
    }

    fun hexToBytes(s: String): ByteArray {
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }
}
