package com.snag

import android.content.Context
import com.snag.core.browser.Browser
import com.snag.core.browser.BrowserImpl
import com.snag.core.config.Config
import com.snag.core.log.LogcatManager
import com.snag.core.utils.AppMetadataProvider
import com.snag.models.*

object Snag {
    private lateinit var appContext: Context
    private lateinit var device: Device
    private lateinit var project: Project

    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: Config = Config.getDefault(context)
    ) {
        this.appContext = context.applicationContext
        this.device = AppMetadataProvider.getDevice()
        this.project = AppMetadataProvider.getProject(context, config.projectName)

        val browser = BrowserImpl(
            context = appContext,
            config = config,
            project = project,
            device = device
        )
        Browser.initialize(browser)

        browser.addPacketListener { packet ->
            packet.control?.let { handleControl(it) }
        }

        // Request initial log streaming status
        browser.sendPacket(Packet(
            control = Control(type = "logStreamingStatusRequest"),
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
            Browser.getInstance()
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
            Browser.getInstance().sendLog(
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
        LogcatManager.startAutoLogCapture()
    }

    private fun handleControl(control: Control) {
        when (control.type) {
            "appInfoRequest" -> sendAppInfo()
            "logStreamingControl" -> {
                LogcatManager.setStreamingEnabled(control.shouldStreamLogs ?: false)
            }
        }
    }

    private fun sendAppInfo() {
        val bundleId = appContext.packageName
        
        val appInfo = AppInfo(
            bundleId = bundleId,
            isReactNative = AppMetadataProvider.isReactNative()
        )
        try {
            Browser.getInstance().sendPacket(Packet(
                control = Control(type = "appInfoResponse", appInfo = appInfo),
                device = device,
                project = project
            ))
        } catch (e: Exception) {
            timber.log.Timber.e(e, "Snag: Failed to send appInfoResponse")
        }
    }
}