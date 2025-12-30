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
