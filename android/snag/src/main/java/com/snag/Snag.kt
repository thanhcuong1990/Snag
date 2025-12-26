package com.snag

import android.content.Context
import android.os.Build
import com.snag.core.browser.Browser
import com.snag.core.browser.BrowserImpl
import com.snag.core.config.Config
import com.snag.models.Device
import com.snag.models.Project

object Snag {
    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: Config = Config.getDefault(context)
    ) {
        val device = Device(
            deviceName = Build.MODEL,
            deviceDescription = "Android ${Build.VERSION.RELEASE}",
            deviceId = "${Build.MANUFACTURER}-${Build.MODEL}-android-${Build.VERSION.RELEASE}"
        )
        val project = Project(projectName = config.projectName)

        val browser = BrowserImpl(
            context = context.applicationContext,
            config = config,
            project = project,
            device = device
        )
        Browser.initialize(browser)
    }
}