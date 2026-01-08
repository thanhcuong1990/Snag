package com.snag.reactnative

import com.facebook.react.modules.network.OkHttpClientFactory
import com.facebook.react.modules.network.OkHttpClientProvider
import com.snag.SnagInterceptor
import okhttp3.OkHttpClient

class SnagOkHttpClientFactory : OkHttpClientFactory {
    override fun createNewNetworkModuleClient(): OkHttpClient {
        return OkHttpClientProvider.createClientBuilder()
            .addInterceptor(SnagInterceptor.getInstance())
            .build()
    }
}
