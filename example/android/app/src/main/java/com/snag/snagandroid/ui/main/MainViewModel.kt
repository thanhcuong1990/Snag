package com.snag.snagandroid.ui.main

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.snag.snagandroid.domain.repository.NetworkRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    private val repository: NetworkRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState = _uiState.asStateFlow()

    fun runTest(testName: String) {
        if (testName == "Multiple Requests Test") {
            _uiState.update { it.copy(isLoading = true, responseText = "Starting multiple requests...\n", loadedImage = null) }
            viewModelScope.launch {
                kotlinx.coroutines.coroutineScope {
                    val delays = listOf(3, 1, 2)
                    delays.forEachIndexed { index, delay ->
                        launch {
                            val result = repository.delayedRequest(delay)
                            val text = result.getOrElse { "Failed: ${it.localizedMessage}" }
                            _uiState.update { state ->
                                state.copy(responseText = state.responseText + "\nRequest ${index + 1} (delay $delay) done.\n$text\n")
                            }
                        }
                    }
                }
                _uiState.update { it.copy(isLoading = false, responseText = it.responseText + "\nAll requests finished.") }
            }
            return
        }

        _uiState.update { it.copy(isLoading = true, responseText = "Loading...", loadedImage = null) }
        viewModelScope.launch {
            val result = when (testName) {
                "GET Post" -> repository.getPost()
                "POST Create" -> repository.createPost(
                    buildJsonObject {
                        put("title", JsonPrimitive("New Post"))
                        put("body", JsonPrimitive("Hello"))
                        put("userId", JsonPrimitive(1))
                    }
                )
                "PUT Update" -> repository.updatePost(
                    buildJsonObject {
                        put("id", JsonPrimitive(1))
                        put("title", JsonPrimitive("Updated"))
                        put("body", JsonPrimitive("Updated"))
                        put("userId", JsonPrimitive(1))
                    }
                )
                "PATCH Partial" -> repository.patchPost(
                    buildJsonObject {
                        put("title", JsonPrimitive("Patched"))
                    }
                )
                "DELETE" -> repository.deletePost()
                "GET Image" -> repository.getImage().map {
                    // Special handling for image result which returns List<Any>
                    _uiState.update { state -> state.copy(loadedImage = it[0] as? Bitmap) }
                    it[1] as String
                }
                "GET Large JSON" -> repository.getLargeJson()
                "Slow Request (Timeout Test)" -> repository.slowRequest()
                "Multipart Upload" -> {
                    val fileBody = "Fake image data".toRequestBody("image/jpeg".toMediaTypeOrNull())
                    val part = MultipartBody.Part.createFormData("image", "photo.jpg", fileBody)
                    val title = "My Vacation Photo".toRequestBody("text/plain".toMediaTypeOrNull())
                    repository.multipartUpload(part, title)
                }
                "Auth Bearer" -> repository.authenticatedRequest("Bearer valid-bearer")
                "Auth Fail (401)" -> repository.authenticatedRequest("Bearer invalid")
                "401 Unauthorized" -> repository.testHttpStatus(401)
                "403 Forbidden" -> repository.testHttpStatus(403)
                "404 Not Found" -> repository.testHttpStatus(404)
                "500 Internal Server Error" -> repository.testHttpStatus(500)
                "503 Service Unavailable" -> repository.testHttpStatus(503)
                "Query Params" -> repository.requestWithQueryParams(mapOf("search" to "swift network", "page" to "1"))
                else -> Result.success("Unknown test")
            }

            _uiState.update { state ->
                state.copy(
                    isLoading = false,
                    responseText = result.getOrElse { "Request failed: ${it.localizedMessage}" }
                )
            }
        }
    }
}

data class MainUiState(
    val responseText: String = "Tap a test to run",
    val isLoading: Boolean = false,
    val loadedImage: Bitmap? = null
)