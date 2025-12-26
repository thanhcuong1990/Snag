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
                requestBody = request.body?.toByteArray()?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
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
                    requestBody = request.body?.toByteArray()?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
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
        requestBody = requestBase64(),
        statusCode = code.toString()
    )

    private fun Response.responseBase64(): String = Base64.encodeToString(
        peekBody(Long.MAX_VALUE).bytes(), Base64.NO_WRAP
    )

    private fun Response.requestBase64(): String = request.body?.toByteArray()?.let {
        Base64.encodeToString(it, Base64.NO_WRAP)
    }.orEmpty()

    private fun RequestBody.toByteArray(): ByteArray? = try {
        val buffer = Buffer().apply {
            writeTo(this)
        }
        buffer.readByteArray()
    } catch (e: Exception) {
        Timber.e(e)
        null
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
