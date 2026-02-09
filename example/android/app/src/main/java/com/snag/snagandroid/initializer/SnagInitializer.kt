package com.snag.snagandroid.initializer

import android.content.Context
import androidx.startup.Initializer
import com.snag.Snag
import com.snag.core.SnagConfiguration
import timber.log.Timber

class SnagInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        applyTrustMigrationIfNeeded(context)

        val config = SnagConfiguration.getDefault(context).copy(
            securityListener = { event ->
                Timber.e(
                    "Snag identity mismatch detected. key=%s expected=%s actual=%s hint=%s",
                    event.serverKey,
                    event.expectedFingerprint,
                    event.actualFingerprint,
                    event.recoveryHint
                )
            }
        )

        Snag.start(context, config)
    }

    override fun dependencies(): MutableList<Class<out Initializer<*>>> =
        mutableListOf(TimberInitializer::class.java)

    private fun applyTrustMigrationIfNeeded(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(TRUST_MIGRATION_KEY, false)) {
            return
        }

        // One-time migration when introducing strict TOFU mismatch enforcement.
        // Existing dev installs may have stale fingerprints from older local identities.
        Snag.resetTrustedServers(context)
        prefs.edit().putBoolean(TRUST_MIGRATION_KEY, true).apply()
    }

    companion object {
        private const val PREFS_NAME = "snag_example_prefs"
        private const val TRUST_MIGRATION_KEY = "tofu_migration_applied_v1"
    }
}
