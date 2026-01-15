package com.snag

import android.content.Context
import com.snag.core.SnagConfiguration
import com.snag.core.log.SnagLogcatManager
import com.snag.core.SnagAppMetadataProvider
import com.snag.interceptors.SnagInterceptor
import com.snag.models.*
import com.snag.network.SnagBrowser
import com.snag.network.SnagBrowserImpl

object Snag {
    private lateinit var appContext: Context
    private lateinit var device: SnagDevice
    private lateinit var project: SnagProject

    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: SnagConfiguration = SnagConfiguration.getDefault(context)
    ) {
        this.appContext = context.applicationContext
        this.device = SnagAppMetadataProvider.getDevice()
        this.project = SnagAppMetadataProvider.getProject(context, config.projectName)

        val browser = SnagBrowserImpl(
            context = appContext,
            config = config,
            project = project,
            device = device
        )
        SnagBrowser.initialize(browser)

        browser.addPacketListener { packet ->
            packet.control?.let { handleControl(it) }
        }

        // Request initial log streaming status
        browser.sendPacket(SnagPacket(
            control = SnagControl(type = "logStreamingStatusRequest"),
            device = device,
            project = project
        ))
        
        if (config.enableLogs) {
            enableAutoLogCapture()
        }
    }

    @JvmStatic
    fun isEnabled(): Boolean {
        return try {
            SnagBrowser.getInstance()
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Helper to manually add Snag interceptor to your OkHttpClient.Builder.
     * Use this if you are not using React Native's default OkHttpClient or want to add it to a specific client.
     */
    @JvmStatic
    fun addInterceptor(builder: okhttp3.OkHttpClient.Builder) {
        // Prevent duplicate interceptors
        if (builder.interceptors().none { it is SnagInterceptor }) {
            builder.addInterceptor(SnagInterceptor.getInstance())
        }
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
        SnagLogcatManager.startAutoLogCapture()
    }

    private fun handleControl(control: SnagControl) {
        when (control.type) {
            "appInfoRequest" -> sendAppInfo()
            "logStreamingControl" -> {
                SnagLogcatManager.setStreamingEnabled(control.shouldStreamLogs ?: false)
            }
        }
    }

    private fun sendAppInfo() {
        val bundleId = appContext.packageName
        
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