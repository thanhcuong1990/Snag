package com.snag.snagandroid.initializer

import android.content.Context
import androidx.startup.Initializer
import com.snag.Snag
import com.snag.core.config.Config

class SnagInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        Snag.start(context, Config.getDefault(context))
    }

    override fun dependencies(): MutableList<Class<out Initializer<*>>> =
        mutableListOf(TimberInitializer::class.java)
}