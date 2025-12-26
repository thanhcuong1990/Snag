package com.snag.snagandroid

import android.app.Application
import android.os.Build
import com.snag.Snag
import com.snag.core.config.Config
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class SnagApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Snag.start(this)
    }
}
