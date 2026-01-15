package com.snag

import com.facebook.react.modules.network.OkHttpClientFactory
import com.facebook.react.modules.network.OkHttpClientProvider
import okhttp3.OkHttpClient
import com.snag.interceptors.SnagInterceptor

class SnagOkHttpClientFactory : OkHttpClientFactory {
    override fun createNewNetworkModuleClient(): OkHttpClient {
        return OkHttpClientProvider.createClientBuilder()
            .addInterceptor(SnagInterceptor.getInstance())
            .build()
    }
}
