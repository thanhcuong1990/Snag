package com.snag

import android.content.Context
import com.snag.core.SnagConfiguration
import com.snag.core.log.SnagLogcatManager
import com.snag.core.SnagAppMetadataProvider
import com.snag.interceptors.SnagInterceptor
import com.snag.models.*
import com.snag.network.SnagBrowser
import com.snag.network.SnagBrowserImpl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object Snag {
    private var appContext: Context? = null
    private lateinit var device: SnagDevice
    private lateinit var project: SnagProject

    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: SnagConfiguration = SnagConfiguration.getDefault(context)
    ) {
        try {
            val appCtx = context.applicationContext ?: context
            this.appContext = appCtx

            val browser = SnagBrowserImpl(
                context = appCtx,
                config = config
            )
            SnagBrowser.initialize(browser)

            browser.addPacketListener { packet ->
                packet.control?.let { handleControl(it) }
            }

            if (config.enableLogs) {
                enableAutoLogCapture()
            }
            
            // Fetch heavy metadata asynchronously
            MainScope().launch(Dispatchers.IO) {
                val fetchedDevice = SnagAppMetadataProvider.getDevice(appCtx)
                val fetchedProject = SnagAppMetadataProvider.getProject(appCtx, config.projectName)

                withContext(Dispatchers.Main) {
                    this@Snag.device = fetchedDevice
                    this@Snag.project = fetchedProject
                    
                    // Now that metadata is ready, start discovery and handshake
                    browser.start(fetchedProject, fetchedDevice)
                    
                    // Request initial log streaming status
                    browser.sendPacket(SnagPacket(
                        control = SnagControl(type = "logStreamingStatusRequest"),
                        device = fetchedDevice,
                        project = fetchedProject
                    ))
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("Snag", "Failed to start Snag", e)
        }
    }

    @JvmStatic
    fun isEnabled(): Boolean {
        return SnagBrowser.isInitialized()
    }

    /**
     * Helper to manually add Snag interceptor to your OkHttpClient.Builder.
     * Use this if you are not using React Native's default OkHttpClient or want to add it to a specific client.
     */
    @JvmStatic
    fun addInterceptor(builder: okhttp3.OkHttpClient.Builder) {
        try {
            // Prevent duplicate interceptors
            if (builder.interceptors().none { it is SnagInterceptor }) {
                builder.addInterceptor(SnagInterceptor.getInstance())
            }
        } catch (_: Exception) { }
    }

    @JvmStatic
    @JvmOverloads
    fun log(
        message: String,
        level: String = "info",
        tag: String? = null,
        details: Map<String, String>? = null
    ) {
        try {
            SnagBrowser.getInstance().sendLog(
                SnagLog(
                    level = level,
                    message = message,
                    tag = tag,
                    details = details
                )
            )
        } catch (_: Exception) {
            // Snag not initialized or failed
        }
    }

    @JvmStatic
    fun enableAutoLogCapture() {
        try {
            SnagLogcatManager.startAutoLogCapture()
        } catch (_: Exception) { }
    }

    private fun handleControl(control: SnagControl) {
        if (!::device.isInitialized || !::project.isInitialized) return
        
        when (control.type) {
            "appInfoRequest" -> sendAppInfo()
            "logStreamingControl" -> {
                SnagLogcatManager.setStreamingEnabled(control.shouldStreamLogs ?: false)
            }
        }
    }

    private fun sendAppInfo() {
        val ctx = appContext ?: return
        if (!::device.isInitialized || !::project.isInitialized) return

        val bundleId = ctx.packageName ?: "unknown"
        
        val appInfo = SnagAppInfo(
            bundleId = bundleId,
            isReactNative = SnagAppMetadataProvider.isReactNative()
        )
        try {
            SnagBrowser.getInstance().sendPacket(SnagPacket(
                control = SnagControl(type = "appInfoResponse", appInfo = appInfo),
                device = device,
                project = project
            ))
        } catch (e: Exception) {
            timber.log.Timber.e(e, "Snag: Failed to send appInfoResponse")
        }
    }
}