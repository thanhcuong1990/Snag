package com.snag.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SnagTrustStoreTest {
    @Test
    fun trustsFirstFingerprintThenRejectsMismatch() {
        val store = SnagTrustStore.createForTesting()

        val first = store.verifyOrTrust(serverKey = "bonjour|demo", fingerprint = "aaa")
        assertTrue(first is SnagTrustDecision.Trusted)

        val second = store.verifyOrTrust(serverKey = "bonjour|demo", fingerprint = "aaa")
        assertTrue(second is SnagTrustDecision.Trusted)

        val mismatch = store.verifyOrTrust(serverKey = "bonjour|demo", fingerprint = "bbb")
        assertTrue(mismatch is SnagTrustDecision.Mismatch)
        val mismatchDecision = mismatch as SnagTrustDecision.Mismatch
        assertEquals("aaa", mismatchDecision.expectedFingerprint)
        assertEquals("bbb", mismatchDecision.actualFingerprint)

        val metrics = store.metricsSnapshot()
        assertEquals(1, metrics.trustedServerCount)
        assertEquals(1, metrics.mismatchCount)
    }
}
