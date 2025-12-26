package com.snag.snagandroid

import android.app.Application
import com.snag.Snag
import com.snag.core.config.Config
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class SnagApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Snag.start(
            context = this,
            config = Config.getDefault(this).copy(
                debugHost = "10.0.2.2" // Emulator loopback to host
            )
        )
    }
}
