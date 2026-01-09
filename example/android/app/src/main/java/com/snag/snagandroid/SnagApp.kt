package com.snag.snagandroid

import android.app.Application
import android.os.Build
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class SnagApp : Application() {
    override fun onCreate() {
        super.onCreate()
    }
}
