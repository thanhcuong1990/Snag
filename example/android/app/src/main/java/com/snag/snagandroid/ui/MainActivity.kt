package com.snag.snagandroid.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.snag.snagandroid.ui.main.MainRoute
import com.snag.snagandroid.ui.main.MainScreen
import com.snag.snagandroid.ui.theme.SnagAndroidTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        
        // Test logs
        android.util.Log.v("SnagExample", "Verbose log message")
        android.util.Log.d("SnagExample", "Debug log message")
        android.util.Log.i("SnagExample", "Info log message")
        android.util.Log.w("SnagExample", "Warning log message")
        android.util.Log.e("SnagExample", "Error log message")
        com.snag.Snag.log("Manual Snag.log message from Android")
        
        // Test JSON log
        val jsonObject = org.json.JSONObject().apply {
            put("user", org.json.JSONObject().apply {
                put("name", "Jane Doe")
                put("email", "jane@example.com")
                put("age", 25)
            })
            put("items", org.json.JSONArray().apply {
                put("orange")
                put("grape")
                put("mango")
            })
            put("isActive", false)
            put("balance", 456.78)
        }
        com.snag.Snag.log(jsonObject.toString(), level = "info", tag = "JSON Test")
        
        setContent {
            SnagAndroidTheme {
                MainApp(modifier = Modifier.fillMaxSize())
            }
        }
    }
}

@Composable
private fun MainApp(
    modifier: Modifier = Modifier,
) {
    MainRoute(
        modifier = modifier
    )
}
