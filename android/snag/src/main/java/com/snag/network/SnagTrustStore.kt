package com.snag.network

import android.content.Context
import com.snag.core.log.SnagInternalLogger
import com.snag.models.SnagTrustMetrics
import java.util.concurrent.atomic.AtomicLong

internal sealed class SnagTrustDecision {
    data object Trusted : SnagTrustDecision()
    data class Mismatch(
        val expectedFingerprint: String,
        val actualFingerprint: String
    ) : SnagTrustDecision()
}

internal class SnagTrustStore private constructor(
    private val storage: Storage
) {
    private val mismatchCounter = AtomicLong(storage.getLong(MISMATCH_COUNT_KEY, 0L))

    @Synchronized
    fun verifyOrTrust(serverKey: String, fingerprint: String): SnagTrustDecision {
        val key = storageKey(serverKey)
        val existing = storage.getString(key)

        if (existing == null) {
            storage.putString(key, fingerprint)
            SnagInternalLogger.d("SnagTrustStore: trusted new server fingerprint for key=%s", serverKey)
            return SnagTrustDecision.Trusted
        }

        val matched = existing.equals(fingerprint, ignoreCase = true)
        if (!matched) {
            val mismatchCount = mismatchCounter.incrementAndGet()
            storage.putLong(MISMATCH_COUNT_KEY, mismatchCount)
            SnagInternalLogger.e("SnagTrustStore: fingerprint mismatch for key=%s", serverKey)
            return SnagTrustDecision.Mismatch(
                expectedFingerprint = existing,
                actualFingerprint = fingerprint
            )
        }
        return SnagTrustDecision.Trusted
    }

    @Synchronized
    fun resetAll() {
        mismatchCounter.set(0)
        storage.clear()
    }

    @Synchronized
    fun metricsSnapshot(): SnagTrustMetrics {
        return SnagTrustMetrics(
            trustedServerCount = storage.keys().count { it.startsWith(FINGERPRINT_KEY_PREFIX) },
            mismatchCount = mismatchCounter.get()
        )
    }

    private fun storageKey(serverKey: String): String {
        return "$FINGERPRINT_KEY_PREFIX${serverKey.lowercase()}"
    }

    private interface Storage {
        fun getString(key: String): String?
        fun putString(key: String, value: String)
        fun getLong(key: String, defaultValue: Long): Long
        fun putLong(key: String, value: Long)
        fun clear()
        fun keys(): Set<String>
    }

    private class SharedPrefsStorage(context: Context) : Storage {
        private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        override fun getString(key: String): String? = prefs.getString(key, null)

        override fun putString(key: String, value: String) {
            prefs.edit().putString(key, value).apply()
        }

        override fun getLong(key: String, defaultValue: Long): Long = prefs.getLong(key, defaultValue)

        override fun putLong(key: String, value: Long) {
            prefs.edit().putLong(key, value).apply()
        }

        override fun clear() {
            prefs.edit().clear().apply()
        }

        override fun keys(): Set<String> = prefs.all.keys
    }

    private class InMemoryStorage(
        initialFingerprints: Map<String, String>,
        private var mismatchCount: Long
    ) : Storage {
        private val map = initialFingerprints.toMutableMap()

        override fun getString(key: String): String? = map[key]

        override fun putString(key: String, value: String) {
            map[key] = value
        }

        override fun getLong(key: String, defaultValue: Long): Long {
            return if (key == MISMATCH_COUNT_KEY) mismatchCount else defaultValue
        }

        override fun putLong(key: String, value: Long) {
            if (key == MISMATCH_COUNT_KEY) {
                mismatchCount = value
            }
        }

        override fun clear() {
            map.clear()
            mismatchCount = 0
        }

        override fun keys(): Set<String> {
            val keys = map.keys.toMutableSet()
            keys.add(MISMATCH_COUNT_KEY)
            return keys
        }
    }

    companion object {
        private const val PREFS_NAME = "snag_trust_store"
        private const val FINGERPRINT_KEY_PREFIX = "fp_"
        private const val MISMATCH_COUNT_KEY = "mismatch_count"

        @Volatile
        private var instance: SnagTrustStore? = null

        fun getInstance(context: Context): SnagTrustStore {
            return instance ?: synchronized(this) {
                instance ?: SnagTrustStore(SharedPrefsStorage(context)).also { instance = it }
            }
        }

        internal fun createForTesting(
            initialFingerprints: Map<String, String> = emptyMap(),
            initialMismatchCount: Long = 0L
        ): SnagTrustStore {
            return SnagTrustStore(
                InMemoryStorage(
                    initialFingerprints = initialFingerprints.mapKeys { "${FINGERPRINT_KEY_PREFIX}${it.key.lowercase()}" },
                    mismatchCount = initialMismatchCount
                )
            )
        }
    }
}
