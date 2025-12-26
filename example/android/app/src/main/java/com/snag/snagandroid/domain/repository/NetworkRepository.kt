package com.snag.snagandroid.domain.repository

import kotlinx.serialization.json.JsonObject
import okhttp3.MultipartBody
import okhttp3.RequestBody

interface NetworkRepository {

    suspend fun getPost(): Result<String>
    suspend fun createPost(body: JsonObject): Result<String>
    suspend fun updatePost(body: JsonObject): Result<String>
    suspend fun patchPost(body: JsonObject): Result<String>
    suspend fun deletePost(): Result<String>
    suspend fun getImage(): Result<List<Any>> // Using List<Any> to hold bitmap or data info as simple return type
    suspend fun getLargeJson(): Result<String>
    suspend fun slowRequest(): Result<String>
    suspend fun multipartUpload(imagePart: MultipartBody.Part, titlePart: RequestBody): Result<String>
    suspend fun authenticatedRequest(auth: String): Result<String>
    suspend fun testHttpStatus(code: Int): Result<String>
    suspend fun requestWithQueryParams(params: Map<String, String>): Result<String>
    suspend fun delayedRequest(seconds: Int): Result<String>
}