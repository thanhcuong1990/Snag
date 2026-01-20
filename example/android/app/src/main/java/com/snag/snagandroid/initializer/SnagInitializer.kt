package com.snag.snagandroid.initializer

import android.content.Context
import androidx.startup.Initializer
import com.snag.Snag
import com.snag.core.SnagConfiguration

class SnagInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        Snag.start(context, SnagConfiguration.getDefault(context))
    }

    override fun dependencies(): MutableList<Class<out Initializer<*>>> =
        mutableListOf(TimberInitializer::class.java)
}