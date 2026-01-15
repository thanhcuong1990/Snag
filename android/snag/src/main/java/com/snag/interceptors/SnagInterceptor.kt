package com.snag.interceptors

import android.util.Base64
import com.snag.network.SnagBrowser
import com.snag.models.SnagRequestInfo
import okhttp3.Interceptor
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import timber.log.Timber
import java.util.UUID

/**
 * OkHttp Interceptor that captures network requests and responses for Snag.
 * 
 * IMPORTANT: This interceptor is designed to be completely non-invasive.
 * It does NOT modify the request or consume the request body before it's sent.
 * Request body is only captured AFTER the response is received (when safe to do so).
 */
class SnagInterceptor private constructor() : Interceptor {

    private val browser by lazy {
        SnagBrowser.getInstance()
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val packetId = UUID.randomUUID().toString()
        val startDateSeconds = System.currentTimeMillis() / 1000.0

        // PHASE 1: Send initial packet with metadata only (NO body read here!)
        // This ensures we don't consume any streams before OkHttp sends the request
        browser.sendPacket(
            requestInfo = SnagRequestInfo(
                url = request.url.toString(),
                requestMethod = request.method,
                requestHeaders = request.headers.toMap(),
                requestBody = null, // Body captured later, after response
                startDate = startDateSeconds
            ),
            packetId = packetId
        )

        // PHASE 2: Execute the original request unchanged
        return try {
            val response = chain.proceed(request)
            
            // PHASE 3: After response, now safe to capture request body
            browser.sendPacket(
                requestInfo = response.toRequestInfo(
                    packetId = packetId,
                    startDateSeconds = startDateSeconds
                ),
                packetId = packetId
            )
            response
        } catch (e: Exception) {
            // On error, send what we have (still no body - can't safely read it)
            browser.sendPacket(
                requestInfo = SnagRequestInfo(
                    url = request.url.toString(),
                    requestMethod = request.method,
                    requestHeaders = request.headers.toMap(),
                    requestBody = null,
                    startDate = startDateSeconds,
                    endDate = System.currentTimeMillis() / 1000.0,
                    statusCode = "ERR"
                ),
                packetId = packetId
            )
            throw e
        }
    }

    /**
     * Converts the Response to RequestInfo, including the request body.
     * This is called AFTER the response is received, so it's safe to read the body.
     */
    private fun Response.toRequestInfo(packetId: String, startDateSeconds: Double): SnagRequestInfo = 
        SnagRequestInfo(
            url = request.url.toString(),
            requestMethod = request.method,
            requestHeaders = request.headers.toMap(),
            responseHeaders = headers.toMap(),
            startDate = startDateSeconds,
            endDate = receivedResponseAtMillis / 1000.0,
            responseData = safeResponseBase64(),
            requestBody = request.body?.safeToBase64(),
            statusCode = code.toString()
        )

    /**
     * Safely reads the response body without consuming it.
     * Uses peekBody() which creates a copy of the body.
     */
    private fun Response.safeResponseBase64(): String = try {
        Base64.encodeToString(peekBody(10 * 1024 * 1024).bytes(), Base64.NO_WRAP)
    } catch (e: Exception) {
        Timber.e(e, "Snag: Failed to read response body")
        ""
    }

    /**
     * Safely converts the request body to a Base64-encoded string.
     * 
     * Returns null for:
     * - One-shot bodies (e.g., multipart uploads from streams) - already consumed
     * - Duplex bodies (e.g., web sockets) - streaming bodies that can't be buffered
     * 
     * Note: This is called AFTER chain.proceed(), so the request has already been sent.
     * For one-shot bodies, the content is already consumed by OkHttp, so we can't capture it.
     * For regular bodies, OkHttp keeps the content available for re-reading.
     */
    private fun RequestBody.safeToBase64(): String? {
        // One-shot bodies have already been consumed by OkHttp
        if (isOneShot()) {
            Timber.d("Snag: One-shot body already consumed (e.g., multipart upload)")
            return null
        }

        // Duplex bodies are streaming and can't be buffered
        if (isDuplex()) {
            Timber.d("Snag: Duplex body cannot be captured (streaming)")
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

