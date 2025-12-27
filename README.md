# Snag

<p align="center">
  <img src="./assets/header.png" width="128" alt="Snag App Icon">
</p>

<p align="center">
    <a href="https://github.com/CocoaPods/CocoaPods" alt="CocoaPods">
        <img src="https://img.shields.io/badge/CocoaPods-compatible-4BC51D.svg?style=flat" />
    </a>
    <a href="https://swift.org/package-manager/" alt="Swift Package Manager">
        <img src="https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat" />
    </a>
    <a href="https://central.sonatype.com/artifact/io.github.thanhcuong1990/snag" alt="Maven Central">
        <img src="https://img.shields.io/maven-central/v/io.github.thanhcuong1990/snag.svg" />
    </a>
    <a href="https://github.com/thanhcuong1990/Snag/releases" alt="Version">
        <img src="https://img.shields.io/github/release/thanhcuong1990/Snag.svg" />
    </a>
</p>

**Snag** is a native network debugger for iOS and Android. No proxies, no certificates, and zero configuration required. It uses **Bonjour** for automatic discovery, allowing you to monitor network traffic in real-time on a desktop viewer over your local network.

## Preview

![Snag Screenshot](./assets/screenshot.png)

## 🖥️ Desktop Viewer (Mac)

1. Clone the repository.
2. Open `mac/Snag.xcodeproj` in Xcode.
3. Build and Run.

---

## 📱 iOS Integration

### Installation

#### Swift Package Manager (Recommended)

Add the package URL to your project:
`https://github.com/thanhcuong1990/Snag.git`

#### CocoaPods

```ruby
pod 'Snag', '~> 1.0.0'
```

### Usage

Initialize Snag in your `AppDelegate` or at the start of your app:

```swift
import Snag

#if DEBUG
Snag.start()
#endif
```

### Configuration (Optional)

```swift
let config = SnagConfiguration()
config.project?.name = "My App"
config.device?.name = "Developer iPhone"

Snag.start(configuration: config)
```

---

## 🤖 Android Integration

### Installation

Add the dependency to your `build.gradle`:

```groovy
implementation 'io.github.thanhcuong1990:snag:1.0.4'
```

For detailed instructions on how to publish this package yourself, see [android/publishing.md](android/publishing.md).

### Usage

Start the client and add the **OkHttp** interceptor:

> Important: Only enable Snag in **non-production** builds (e.g. debug/staging). Do not initialize Snag or attach the interceptor in release/production.

In the snippets below, `BuildConfig` refers to your **app module** `BuildConfig`.

**Option A: Simple Android setup (you control the OkHttpClient)**

```kotlin

import android.content.Context
import com.snag.Snag

fun initSnagIfNonProd(context: Context) {
  if (BuildConfig.DEBUG || BuildConfig.FLAVOR == "staging") {
    Snag.start(context.applicationContext)
  }
}
```

```kotlin
import com.snag.SnagInterceptor
import okhttp3.OkHttpClient

fun buildOkHttpClient(): OkHttpClient {
  val builder = OkHttpClient.Builder()
  if (BuildConfig.DEBUG || BuildConfig.FLAVOR == "staging") {
    builder.addInterceptor(SnagInterceptor.getInstance())
  }
  return builder.build()
}
```

**Option B: React Native setup (OkHttpClientProvider + reflection-safe initializer)**

Create `NetworkDebugInitializer.kt` (for example: `android/app/src/main/java/your/package/name/NetworkDebugInitializer.kt`)

```kotlin
package your.package.name

import android.content.Context
import android.util.Log
import com.facebook.react.modules.network.OkHttpClientProvider
import okhttp3.Interceptor
import okhttp3.OkHttpClient

object NetworkDebugInitializer {

  private const val TAG = "NetworkDebugInitializer"
  private const val SNAG_CLASS = "com.snag.Snag"
  private const val SNAG_INTERCEPTOR_CLASS = "com.snag.SnagInterceptor"

  private val isDebugOrStaging: Boolean
    get() = BuildConfig.DEBUG || BuildConfig.FLAVOR == "staging"

  fun initForReactNative(context: Context, existingBuilder: OkHttpClient.Builder? = null): Boolean {
    if (!isDebugOrStaging || !isAvailable()) return false

    startIfAvailable(context)
    configureOkHttpClientProvider(context, existingBuilder)
    return true
  }

  fun isAvailable(): Boolean =
    try {
      Class.forName(SNAG_CLASS)
      Class.forName(SNAG_INTERCEPTOR_CLASS)
      true
    } catch (_: Throwable) {
      false
    }

  private fun startIfAvailable(context: Context) =
    runCatching {
        val snagClass = Class.forName(SNAG_CLASS)
        val startMethod = snagClass.getMethod("start", Context::class.java)
        startMethod.invoke(null, context)
      }
      .onFailure { Log.d(TAG, "Snag.start() not available: ${it.message}") }

  private fun configureOkHttpClientProvider(
    context: Context,
    existingBuilder: OkHttpClient.Builder? = null,
  ) {
    val appContext = context.applicationContext
    OkHttpClientProvider.setOkHttpClientFactory {
      val builder = existingBuilder ?: OkHttpClientProvider.createClientBuilder(appContext)
      addSnagInterceptorIfAvailable(builder)
      builder.build()
    }
  }

  private fun addSnagInterceptorIfAvailable(builder: OkHttpClient.Builder) {
    if (builder.interceptors().any { it.javaClass.name == SNAG_INTERCEPTOR_CLASS }) return

    runCatching {
        val interceptorClass = Class.forName(SNAG_INTERCEPTOR_CLASS)
        val getInstanceMethod = interceptorClass.getMethod("getInstance")
        val interceptor = getInstanceMethod.invoke(null) as? Interceptor
        interceptor?.let(builder::addInterceptor) ?: Log.d(TAG, "SnagInterceptor instance is null")
      }
      .onFailure { Log.d(TAG, "SnagInterceptor not available: ${it.message}") }
  }
}
```

Call it from your `MainApplication.kt`:

```kotlin
override fun onCreate() {
  super.onCreate()
  NetworkDebugInitializer.initForReactNative(applicationContext)
}
```

---

## License

Apache License 2.0
