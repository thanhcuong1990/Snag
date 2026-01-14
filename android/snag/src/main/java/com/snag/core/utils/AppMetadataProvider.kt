package com.snag.core.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.util.Base64
import androidx.core.graphics.createBitmap
import com.snag.models.Device
import com.snag.models.Project
import java.io.ByteArrayOutputStream

object AppMetadataProvider {

    fun getDevice(): Device {
        return Device(
            deviceName = Build.MODEL,
            deviceDescription = "Android ${Build.VERSION.RELEASE}",
            deviceId = "${Build.MANUFACTURER}-${Build.MODEL}-android-${Build.VERSION.RELEASE}"
        )
    }

    fun getProject(context: Context, projectName: String): Project {
        return Project(
            projectName = projectName,
            appIcon = getAppIconBase64(context)
        )
    }

    fun isReactNative(): Boolean {
        return try {
            Class.forName("com.facebook.react.bridge.ReactContext")
            true
        } catch (_: Exception) {
            false
        }
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
                val bitmap = createBitmap(width, height)
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
