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
implementation 'io.github.thanhcuong1990:snag:1.0.1'
```

For detailed instructions on how to publish this package yourself, see [android/publishing.md](android/publishing.md).

### Usage

Start the client and add the **OkHttp** interceptor:

```kotlin
// 1. Initialise in Application class
Snag.start(context)

// 2. Add to OkHttpClient
val okHttpClient = OkHttpClient.Builder()
    .addInterceptor(SnagInterceptor.getInstance())
    .build()
```

---

## License

Apache License 2.0
