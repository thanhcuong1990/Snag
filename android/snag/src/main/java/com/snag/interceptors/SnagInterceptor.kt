package com.snag.interceptors

import android.util.Base64
import com.snag.core.log.SnagInternalLogger
import com.snag.network.SnagBrowser
import com.snag.models.SnagRequestInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import java.util.UUID

/**
 * OkHttp Interceptor that captures network requests and responses for Snag.
 *
 * Designed to be non-invasive: it does not modify the request, and request body capture
 * happens AFTER the response is received. Body bytes are buffered in memory bounded by
 * `maxBodyCaptureBytes`; Base64 encoding and packet shipping are dispatched to a
 * background coroutine so the OkHttp call thread is not blocked by encoding.
 */
class SnagInterceptor private constructor() : Interceptor {

    private val browser by lazy { SnagBrowser.getInstance() }
    private val captureScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val packetId = UUID.randomUUID().toString()
        val startDateSeconds = System.currentTimeMillis() / 1000.0

        browser.sendPacket(
            requestInfo = SnagRequestInfo(
                url = request.url.toString(),
                requestMethod = request.method,
                requestHeaders = request.headers.toMap(),
                requestBody = null,
                startDate = startDateSeconds
            ),
            packetId = packetId
        )

        return try {
            val response = chain.proceed(request)

            val cap = maxBodyCaptureBytes
            val (responseBytes, responseTruncated) = captureResponseBytes(response, cap)
            val (requestBytes, requestTruncated) = captureRequestBytes(request.body, request.headers, cap)

            val endDateSeconds = response.receivedResponseAtMillis / 1000.0
            val responseHeaders = response.headers.toMap()
            val statusCode = response.code.toString()

            captureScope.launch {
                val responseB64 = responseBytes?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
                val requestB64 = requestBytes?.let { Base64.encodeToString(it, Base64.NO_WRAP) }

                browser.sendPacket(
                    requestInfo = SnagRequestInfo(
                        url = request.url.toString(),
                        requestMethod = request.method,
                        requestHeaders = request.headers.toMap(),
                        responseHeaders = responseHeaders,
                        startDate = startDateSeconds,
                        endDate = endDateSeconds,
                        responseData = responseB64,
                        requestBody = requestB64,
                        statusCode = statusCode,
                        requestBodyTruncated = if (requestTruncated) true else null,
                        responseBodyTruncated = if (responseTruncated) true else null
                    ),
                    packetId = packetId
                )
            }

            response
        } catch (e: Exception) {
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

    private fun captureResponseBytes(response: Response, cap: Int): Pair<ByteArray?, Boolean> {
        if (shouldSkipBody(response.headers)) return null to false

        val contentLength = response.body?.contentLength() ?: -1L
        if (contentLength > cap) return null to true

        return try {
            val bytes = response.peekBody(cap.toLong()).bytes()
            val truncated = contentLength == -1L && bytes.size >= cap
            bytes to truncated
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Snag: Failed to read response body")
            null to false
        }
    }

    private fun captureRequestBytes(body: RequestBody?, requestHeaders: Headers, cap: Int): Pair<ByteArray?, Boolean> {
        if (body == null) return null to false
        if (body.isOneShot() || body.isDuplex()) return null to false
        if (shouldSkipBody(requestHeaders)) return null to false

        val contentLength = try { body.contentLength() } catch (_: Exception) { -1L }
        if (contentLength > cap) return null to true
        if (contentLength < 0) return null to true

        return try {
            val buffer = Buffer()
            body.writeTo(buffer)
            if (buffer.size > cap) {
                val capped = ByteArray(cap)
                buffer.readFully(capped)
                capped to true
            } else {
                buffer.readByteArray() to false
            }
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Snag: Failed to read request body")
            null to false
        }
    }

    private fun shouldSkipBody(headers: Headers): Boolean {
        val contentType = headers["Content-Type"]?.lowercase() ?: return false
        return SKIP_PREFIXES.any { contentType.startsWith(it) } ||
                SKIP_EXACT.any { contentType.startsWith(it) }
    }

    internal fun shutdown() {
        captureScope.cancel()
    }

    companion object {
        @Volatile
        private var instance: SnagInterceptor? = null

        @Volatile
        private var maxBodyCaptureBytes: Int = 1_048_576

        private val SKIP_PREFIXES = listOf("multipart/", "image/", "video/", "audio/")
        private val SKIP_EXACT = listOf("application/octet-stream")

        @JvmStatic
        fun getInstance(): SnagInterceptor =
            instance ?: synchronized(this) {
                instance ?: SnagInterceptor().also { instance = it }
            }

        @JvmStatic
        fun configure(maxBodyCaptureBytes: Int) {
            this.maxBodyCaptureBytes = maxBodyCaptureBytes.coerceAtLeast(0)
        }

        internal fun shutdownIfStarted() {
            instance?.shutdown()
            instance = null
        }
    }
}
