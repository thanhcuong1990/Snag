package com.snag

import android.util.Base64
import com.snag.core.browser.Browser
import com.snag.models.RequestInfo
import okhttp3.Interceptor
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import timber.log.Timber
import java.util.UUID

class SnagInterceptor private constructor() : Interceptor {

    private val browser by lazy {
        Browser.getInstance()
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val packetId = UUID.randomUUID().toString()
        val startDateSeconds = System.currentTimeMillis() / 1000.0

        browser.sendPacket(
            requestInfo = RequestInfo(
                url = request.url.toString(),
                requestMethod = request.method,
                requestHeaders = request.headers.toMap(),
                requestBody = request.body?.safeToBase64(),
                startDate = startDateSeconds
            ),
            packetId = packetId
        )

        return try {
            val response = chain.proceed(request)
            browser.sendPacket(
                requestInfo = response.requestInfo(packetId = packetId, startDateSeconds = startDateSeconds),
                packetId = packetId
            )
            response
        } catch (e: Exception) {
            browser.sendPacket(
                requestInfo = RequestInfo(
                    url = request.url.toString(),
                    requestMethod = request.method,
                    requestHeaders = request.headers.toMap(),
                    requestBody = request.body?.safeToBase64(),
                    startDate = startDateSeconds,
                    endDate = System.currentTimeMillis() / 1000.0,
                    statusCode = "ERR"
                ),
                packetId = packetId
            )
            throw e
        }
    }

    private fun Response.requestInfo(packetId: String, startDateSeconds: Double): RequestInfo = RequestInfo(
        url = request.url.toString(),
        requestMethod = request.method,
        requestHeaders = request.headers.toMap(),
        responseHeaders = headers.toMap(),
        startDate = startDateSeconds,
        endDate = receivedResponseAtMillis / 1000.0,
        responseData = responseBase64(),
        requestBody = request.body?.safeToBase64(),
        statusCode = code.toString()
    )

    private fun Response.responseBase64(): String = try {
        Base64.encodeToString(peekBody(10 * 1024 * 1024).bytes(), Base64.NO_WRAP)
    } catch (e: Exception) {
        ""
    }

    /**
     * Safely converts the request body to a Base64-encoded string.
     * 
     * Returns null for:
     * - One-shot bodies (e.g., multipart uploads from streams) - can only be consumed once
     * - Duplex bodies (e.g., web sockets) - streaming bodies that can't be buffered
     * 
     * This prevents consuming the body before OkHttp sends it over the network.
     */
    private fun RequestBody.safeToBase64(): String? {
        // One-shot bodies (like multipart from InputStream) can only be consumed once.
        // Reading them here would exhaust the stream before OkHttp sends the request.
        if (isOneShot()) {
            Timber.d("Snag: Skipping one-shot body (e.g., multipart upload)")
            return null
        }

        // Duplex bodies are used for streaming (e.g., web sockets).
        // They can't be buffered safely.
        if (isDuplex()) {
            Timber.d("Snag: Skipping duplex body (streaming)")
            return null
        }

        return try {
            val buffer = Buffer()
            this.writeTo(buffer)
            Base64.encodeToString(buffer.readByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Timber.e(e, "Snag: Failed to read request body")
            null
        }
    }

    companion object {
        @Volatile
        private var instance: SnagInterceptor? = null

        @JvmStatic
        fun getInstance(): SnagInterceptor =
            instance ?: synchronized(this) {
                instance ?: SnagInterceptor().also { instance = it }
            }
    }
}
