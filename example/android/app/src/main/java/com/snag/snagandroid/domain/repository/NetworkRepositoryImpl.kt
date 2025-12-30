package com.snag.snagandroid.domain.repository

import android.graphics.BitmapFactory
import com.snag.snagandroid.remote.NetworkService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NetworkRepositoryImpl @Inject constructor(
    private val networkService: NetworkService
) : NetworkRepository {

    private suspend fun safeApiCall(apiCall: suspend () -> Response<ResponseBody>): Result<String> {
        return withContext(Dispatchers.IO) {
            try {
                val response = apiCall()
                if (response.isSuccessful) {
                    val body = response.body()?.string()
                    // Allow empty body (treat as empty string) to handle cases like 204 No Content
                    if (body != null) {
                        Result.success(body)
                    } else {
                        // For empty body with successful code (e.g. DELETE), return empty success string
                        Result.success("")
                    }
                } else {
                    val errorBody = response.errorBody()?.string()
                    Result.failure(IOException("Error: ${response.code()} ${response.message()} - $errorBody"))
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }

    override suspend fun getPost(): Result<String> = safeApiCall { networkService.getPost() }

    override suspend fun createPost(body: JsonObject): Result<String> = safeApiCall { networkService.createPost(body) }

    override suspend fun updatePost(body: JsonObject): Result<String> = safeApiCall { networkService.updatePost(body) }

    override suspend fun patchPost(body: JsonObject): Result<String> = safeApiCall { networkService.patchPost(body) }

    override suspend fun deletePost(): Result<String> = safeApiCall { networkService.deletePost() }

    override suspend fun getImage(): Result<List<Any>> {
        return withContext(Dispatchers.IO) {
            try {
                val response = networkService.getImage()
                if (response.isSuccessful) {
                    val body = response.body()
                    if (body != null) {
                        val bytes = body.bytes()
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        Result.success(listOf(bitmap, "Status: ${response.code()}\nSize: ${bytes.size} bytes"))
                    } else {
                        Result.failure(IOException("Response body is empty"))
                    }
                } else {
                    Result.failure(IOException("Error: ${response.code()} ${response.message()}"))
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }

    override suspend fun getLargeJson(): Result<String> = safeApiCall { networkService.getLargeJson() }
    
    override suspend fun postLargeJson(body: JsonObject): Result<String> = safeApiCall { networkService.postLargeJson(body) }

    override suspend fun slowRequest(): Result<String> = safeApiCall { networkService.slowRequest() }

    override suspend fun multipartUpload(imagePart: MultipartBody.Part, titlePart: RequestBody): Result<String> =
        safeApiCall { networkService.multipartUpload(imagePart, titlePart) }

    override suspend fun authenticatedRequest(auth: String): Result<String> = safeApiCall { networkService.authenticatedRequest(auth) }

    override suspend fun testHttpStatus(code: Int): Result<String> = safeApiCall { networkService.testHttpStatus(code) }

    override suspend fun requestWithQueryParams(params: Map<String, String>): Result<String> =
        safeApiCall { networkService.requestWithQueryParams(params) }

    override suspend fun delayedRequest(seconds: Int): Result<String> = safeApiCall { networkService.delayedRequest(seconds) }
}