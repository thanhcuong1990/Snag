package com.snag.core.config

import android.content.Context

data class Config(
    val projectName: String,
    val netServiceType: String = "_Snag._tcp",
    val debugHost: String? = null,
    val debugPort: Int = 43435
) {
    companion object {
        fun getDefault(context: Context): Config {
            return Config(
                projectName = context.applicationInfo.loadLabel(context.packageManager).toString()
            )
        }
    }
}
