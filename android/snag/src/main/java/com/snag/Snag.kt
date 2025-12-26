package com.snag

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.util.Base64
import com.snag.core.browser.Browser
import com.snag.core.browser.BrowserImpl
import com.snag.core.config.Config
import com.snag.models.Device
import com.snag.models.Project
import java.io.ByteArrayOutputStream

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
        val project = Project(
            projectName = config.projectName,
            appIcon = getAppIconBase64(context)
        )

        val browser = BrowserImpl(
            context = context.applicationContext,
            config = config,
            project = project,
            device = device
        )
        Browser.initialize(browser)
    }

    private fun getAppIconBase64(context: Context): String? {
        return try {
            val packageManager = context.packageManager
            val applicationInfo = context.applicationInfo
            val icon = packageManager.getApplicationIcon(applicationInfo)
            
            val bitmap = if (icon is BitmapDrawable) {
                icon.bitmap
            } else {
                val width = icon.intrinsicWidth.takeIf { it > 0 } ?: 100
                val height = icon.intrinsicHeight.takeIf { it > 0 } ?: 100
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                icon.setBounds(0, 0, canvas.width, canvas.height)
                icon.draw(canvas)
                bitmap
            }
            
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val byteArray = outputStream.toByteArray()
            Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }
}