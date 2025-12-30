package com.snag.snagandroid.ui.main

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.snag.snagandroid.R

@Composable
fun MainRoute(modifier: Modifier = Modifier) {
    val viewModel = hiltViewModel<MainViewModel>()
    val uiState by viewModel.uiState.collectAsState()

    MainScreen(
        modifier = modifier,
        state = uiState,
        onRunTest = viewModel::runTest
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    modifier: Modifier = Modifier,
    state: MainUiState,
    onRunTest: (String) -> Unit
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Share, // Using a standard icon
                            contentDescription = null,
                            tint = Color.Blue,
                            modifier = Modifier.size(32.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("API Tester", fontWeight = FontWeight.Bold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.White
                )
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .background(Color(0xFFF2F2F7)) // System grouped background
        ) {
            LazyColumn(
                modifier = Modifier.weight(0.5f),
                contentPadding = PaddingValues(16.dp)
            ) {
                testCategories.keys.sorted().forEach { category ->
                    item {
                        Text(
                            text = category.uppercase(),
                            style = MaterialTheme.typography.labelMedium,
                            color = Color.Gray,
                            modifier = Modifier.padding(vertical = 8.dp, horizontal = 16.dp)
                        )
                    }
                    items(testCategories[category] ?: emptyList()) { test ->
                        Button(
                            onClick = { onRunTest(test) },
                            enabled = !state.isLoading,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(imageVector = getIconForTest(test), contentDescription = null)
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(test)
                            }
                        }
                    }
                }
            }

            Box(modifier = Modifier.height(1.dp).fillMaxWidth().background(Color.LightGray))
            
            Column(
                modifier = Modifier
                    .weight(0.5f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp)
            ) {
                // Image Preview
                if (state.loadedImage != null) {
                    Image(
                        bitmap = state.loadedImage.asImageBitmap(),
                        contentDescription = "Loaded Image",
                        modifier = Modifier
                            .height(200.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .align(Alignment.CenterHorizontally)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Response View
                ResponseView(
                    responseText = state.responseText,
                    isLoading = state.isLoading,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
fun ResponseView(
    responseText: String,
    isLoading: Boolean,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Response", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.weight(1f))
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp))
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFFE5E5EA), RoundedCornerShape(10.dp))
                .padding(12.dp)
        ) {
            Text(
                text = responseText,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
            )
        }
    }
}

// Helper to map tests to categories
val testCategories = mapOf(
    "CRUD" to listOf("GET Post", "POST Create", "PUT Update", "PATCH Partial", "DELETE"),
    "Image & JSON" to listOf("GET Image", "GET Large JSON", "POST Large JSON", "Slow Request (Timeout Test)"),
    "Auth & Status" to listOf("Auth Bearer", "Auth Fail (401)", "401 Unauthorized", "403 Forbidden", "404 Not Found", "500 Internal Server Error", "503 Service Unavailable"),
    "Upload" to listOf("Multipart Upload"),
    "Other" to listOf("Query Params", "Multiple Requests Test")
)

fun getIconForTest(test: String): ImageVector {
    return when (test) {
        "GET Post", "GET Image", "GET Large JSON", "POST Large JSON", "Query Params" -> Icons.Default.Warning // Placeholder for arrow down
        "POST Create", "Multipart Upload" -> Icons.Default.Warning // Placeholder for arrow up
        "Auth Bearer", "Auth Fail (401)" -> Icons.Default.Lock
        else -> Icons.Default.Warning // Default generic icon
    }
}
