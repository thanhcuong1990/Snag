package com.snag.core.log

import timber.log.Timber

internal object SnagInternalLogger {
    @Volatile
    private var enabled: Boolean = false

    fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
    }

    fun d(message: String, vararg args: Any?) {
        if (!enabled) return
        Timber.d(message, *args)
    }

    fun w(message: String, vararg args: Any?) {
        if (!enabled) return
        Timber.w(message, *args)
    }

    fun w(throwable: Throwable, message: String, vararg args: Any?) {
        if (!enabled) return
        Timber.w(throwable, message, *args)
    }

    fun e(message: String, vararg args: Any?) {
        Timber.e(message, *args)
    }

    fun e(throwable: Throwable, message: String, vararg args: Any?) {
        Timber.e(throwable, message, *args)
    }
}
