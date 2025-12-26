package com.snag.snagandroid.remote

import kotlinx.serialization.json.JsonObject
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface NetworkService {

    @GET("https://jsonplaceholder.typicode.com/posts/1")
    suspend fun getPost(): Response<ResponseBody>

    @POST("https://jsonplaceholder.typicode.com/posts")
    suspend fun createPost(@Body body: JsonObject): Response<ResponseBody>

    @PUT("https://jsonplaceholder.typicode.com/posts/1")
    suspend fun updatePost(@Body body: JsonObject): Response<ResponseBody>

    @PATCH("https://jsonplaceholder.typicode.com/posts/1")
    suspend fun patchPost(@Body body: JsonObject): Response<ResponseBody>

    @DELETE("https://jsonplaceholder.typicode.com/posts/1")
    suspend fun deletePost(): Response<ResponseBody>

    @GET("https://picsum.photos/800/600")
    suspend fun getImage(): Response<ResponseBody>

    @GET("https://jsonplaceholder.typicode.com/posts")
    suspend fun getLargeJson(): Response<ResponseBody>

    @GET("https://httpbin.org/delay/8")
    suspend fun slowRequest(): Response<ResponseBody>

    @POST("https://httpbin.org/post")
    @Multipart
    suspend fun multipartUpload(@Part image: MultipartBody.Part, @Part("title") title: RequestBody): Response<ResponseBody>

    @GET("https://httpbin.org/bearer")
    suspend fun authenticatedRequest(@Header("Authorization") auth: String): Response<ResponseBody>

    @GET("https://httpbin.org/status/{code}")
    suspend fun testHttpStatus(@Path("code") code: Int): Response<ResponseBody>

    @GET("https://httpbin.org/get")
    suspend fun requestWithQueryParams(@QueryMap params: Map<String, String>): Response<ResponseBody>

    @GET("https://httpbin.org/delay/{seconds}")
    suspend fun delayedRequest(@Path("seconds") seconds: Int): Response<ResponseBody>
}