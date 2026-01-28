# Snag

<p align="center">
  <img src="https://raw.githubusercontent.com/thanhcuong1990/Snag/main/assets/header.png" width="128" alt="Snag App Icon">
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

## 🔄 Connection Flow

Snag uses a secure connection flow to ensure your network traffic remains private. It balances high security with a "zero-config" developer experience:

### Smart Security (TLS + PIN)

All traffic is encrypted via TLS. Snag intelligently manages trust to minimize friction. **Security is enabled by default** in the client libraries.

- **Auto-Trust**: Connections from **Simulators** or via **USB/Wired** are automatically trusted.
- **Interactive Pairing**: For remote connections over **Wi-Fi**, devices appear in the Mac app sidebar with a **Locked (🔒)** icon. To trust a device, click **"Authorize Device"** and enter the **Security PIN** that you configured on the client (iOS/Android).
- **Persistent Trust**: Once authorized, the device is remembered and does not need to be authorized again.

> [!NOTE]
> **Privacy Isolation**: By default, new Wi-Fi devices are blocked (locked) until you explicitly authorize them. This ensures you never receive logs from unauthorized sources.

```mermaid
sequenceDiagram
    participant Client as iOS/Android Client
    participant Server as Mac App (Snag)

    Client->>Server: Connect (TLS)
    Server-->>Client: TLS Handshake (Self-signed Cert)

    alt Auto-Trust (Simulator/USB)
        Server->>Server: Check NWPath (Loopback/Wired)
        Server-->>Client: Mark Connection as Trusted
    else Wi-Fi Connection (Remote)
        Client->>Server: Connect without PIN
        Server-->>Client: Connection Accepted (Untrusted)
        Server->>Server: Show "Locked" Device in Sidebar

        opt User Clicks "Authorize"
            Server->>User: Prompt for PIN
            User->>Server: Input PIN (Matching Client)
            alt PIN matches client value
                Server->>Server: Mark Device ID as Trusted
                Server-->>Client: Start Processing Packets
            end
        end
    end

    Note over Client,Server: Only Trusted/Authorized Connections can exchange data
    Client->>Server: Send encrypted SnagPacket
```

### 🛡️ Security Verification

You can verify that traffic is encrypted using **Wireshark**:

1.  Capture traffic on your local network interface.
2.  Filter by port: `tcp.port == 43435`.
3.  You will see the **TLS Handshake** and all subsequent packets marked as **Application Data**. The payload will be encrypted and unreadable.

![Wireshark Verification](https://raw.githubusercontent.com/thanhcuong1990/Snag/main/assets/wireshark_verify.png)

## Preview

![Snag Screenshot](https://raw.githubusercontent.com/thanhcuong1990/Snag/main/assets/screenshot.png)

## 🖥️ Desktop Viewer (Mac)

### Download from GitHub Releases (Recommended)

1. Download the latest `Snag_<version>.dmg` from the [Releases](https://github.com/thanhcuong1990/Snag/releases) page.
2. Open the DMG and drag `Snag.app` to your Applications folder.
3. **Important**: Since the app is not notarized, macOS will block it by default. Run the following command to remove the quarantine attribute:

```bash
sudo xattr -rd com.apple.quarantine "/Applications/Snag.app/"
```

4. Launch Snag from your Applications folder.

### Build from Source

1. Clone the repository.
2. Open `mac/Snag.xcodeproj` in Xcode.
3. Build and Run.

### 🔐 Device Authorization

When a new device connects via **Wi-Fi**, it will appear in the sidebar with a **Locked (🔒)** icon.

1. Select the locked device in the sidebar.
2. Click the **"Authorize Device"** button at the bottom of the sidebar.
3. Enter the **Security PIN** that was configured on that client.
4. The device is now trusted and logs will start flowing immediately.

![Device Authorization](https://raw.githubusercontent.com/thanhcuong1990/Snag/main/assets/device_auth.png)

### Build DMG + upload to GitHub Releases (local)

Prerequisites:

- `gh` installed and authenticated (`gh auth login`)
- Xcode command line tools installed

Commands:

```bash
chmod +x scripts/release_macos_dmg.sh
./scripts/release_macos_dmg.sh
```

This builds `Snag.app` (Release, signing disabled), creates `dist/Snag_<version>.dmg`, then uploads it to the GitHub Release tag `v<version>` (derived from `mac/Snag/App/Info.plist`).

---

## 📱 iOS Integration

### Installation

#### Swift Package Manager (Recommended)

Add the package URL to your project:
`https://github.com/thanhcuong1990/Snag.git`

#### CocoaPods

```ruby
pod 'Snag', '~> 1.0.21'
```

### Usage

Snag is **zero-config** on iOS. Just add the dependency and it will automatically initialize itself in **Debug** builds.

> [!IMPORTANT]
> Snag uses an Objective-C loader to start automatically. This ensures it **only runs in DEBUG builds**, keeping your production app clean.

### Enable via Info.plist (e.g. for Staging)

By default, Snag only runs in DEBUG builds. To force-enable it (e.g. for Staging), add `SnagEnabled` (Boolean) to your `Info.plist`:

```xml
<key>SnagEnabled</key>
<true/>
```

### Enable via Launch Argument (Xcode Scheme)

You can force-enable Snag or set the security PIN using launch arguments:

1.  In Xcode, go to **Product** > **Scheme** > **Edit Scheme...**
2.  Select **Run** from the left sidebar.
3.  Go to the **Arguments** tab.
4.  Under **Arguments Passed On Launch**, click **+** and add:
    - `-SnagEnabled` (to force-enable Snag)
    - `-SnagSecurityPIN 123456` (to set the security PIN)

### Configure via Info.plist

You can also configure Snag via your `Info.plist`:

```xml
<!-- Force enable Snag (e.g. for Staging) -->
<key>SnagEnabled</key>
<true/>

<!-- Set security PIN -->
<key>SnagSecurityPIN</key>
<string>123456</string>
```

### Manual Initialization (Optional)

If you need to start Snag manually (e.g. for specific configurations):

```swift
import Snag

Snag.start()
```

### Local Network permissions (required on real devices)

Add the following to your app's `Info.plist` to allow Bonjour discovery on a real device:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses the local network to discover nearby devices using Bonjour.</string>
<key>NSBonjourServices</key>
<array>
    <string>_Snag._tcp</string>
</array>
```

### Configuration (Optional)

```swift
let config = SnagConfiguration()
config.project?.name = "My App"
config.device?.name = "Developer iPhone"

// Security Configuration
config.isSecurityEnabled = true
config.securityPIN = "123456" // This PIN must be entered on the Mac app for authorization

Snag.start(configuration: config)
```

### Logging

Snag automatically captures logs from your application and displays them in the desktop viewer.

- **Automatic Capture**: Intercepts `print`, `NSLog`, and `OSLog` (iOS 15+) messages.
- **Manual Logging**: Send custom logs using `Snag.log("message")`.

To disable automatic log capture:

```swift
let config = SnagConfiguration()
config.enableLogs = false
Snag.start(configuration: config)
```

---

## 🤖 Android Integration

### Installation

```groovy
// Use debugImplementation to automatically exclude Snag from release builds
debugImplementation 'io.github.thanhcuong1990:snag:1.0.5'
```

> [!TIP]
> Using `debugImplementation` is the recommended way to ensure Snag is not included in your production APK.

For detailed instructions on how to publish this package yourself, see [android/publishing.md](android/publishing.md).

### Usage

Snag is **zero-config** on Android. Just add the dependency and it will automatically:

1. Initialize itself on app startup.
2. Intercept and debug **OkHttp** requests (including those from **React Native**).
3. Capture **Logcat** logs.

> [!IMPORTANT]
> Snag only initializes itself if it detects that the app is debuggable or running in an emulator.

### Custom OkHttp Client

If you use a custom `OkHttpClient` (or want to use it with Retrofit/Apollo), you can manually add the Snag interceptor:

```kotlin
val builder = OkHttpClient.Builder()
Snag.addInterceptor(builder) // Safe to call multiple times
```

### Enable/Configure via Manifest (e.g. for Staging)

By default, Snag only runs in debug builds or simulators, and security is enabled. To force-enable it, disable security, or set a custom PIN, add this to your `AndroidManifest.xml`:

```xml
<!-- Force enable Snag -->
<meta-data
    android:name="com.snag.ENABLED"
    android:value="true" />

<!-- Disable Smart Security -->
<meta-data
    android:name="com.snag.SECURITY_ENABLED"
    android:value="false" />

<!-- Set security PIN -->
<meta-data
    android:name="com.snag.SECURITY_PIN"
    android:value="123456" />
```

> [!TIP]
> You can also set the PIN via System Properties (e.g., in tests or via ADB) by setting `SnagSecurityPIN`.

### Manual Initialization (Optional)

If you want to customize other configuration options:

```kotlin
import com.snag.Snag
import com.snag.core.SnagConfiguration

val config = SnagConfiguration(
    projectName = "Custom Project Name",
    enableLogs = true,
    isSecurityEnabled = true,
    securityPIN = "123456" // This PIN must be entered on the Mac app for authorization
)
Snag.start(context, config)
```

### Logging

Snag automatically captures `Logcat` output and displays it in the desktop viewer.

- **Automatic Capture**: Intercepts standard Android logs (`Log.v`, `Log.d`, etc.).
- **Manual Logging**: Send custom logs using `Snag.log("message")`.

To disable automatic log capture:

```kotlin
// In your initialization logic
val config = SnagConfiguration.getDefault(context).copy(enableLogs = false)
Snag.start(context, config)
```

---

## ⚛️ React Native Integration

Snag provides a **truly zero-config** experience for React Native.

### 1. Zero-Config (Recommended)

Just add the native Snag library to your `ios` and `android` projects as described above. Snag will automatically:

- Intercept `console.log`, `console.warn`, and `console.error`.
- Capture all network requests (`fetch`, `XMLHttpRequest`).
- **No JavaScript changes or imports required.**

### 2. Manual Logging & Object Inspection

If you want to log complex objects or use custom tags from JavaScript, you can use the `react-native-snag` wrapper.

#### Installation

```bash
npm install react-native-snag
```

#### Usage

```javascript
import Snag from "react-native-snag";

// Manual logging with tags
Snag.log("User logged in", "info", "Auth");

// Note: console.log is already handled by the native hooks.
// Use Snag.log when you need more control.
```

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add some amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Guidelines

- Please ensure your code follows the existing code style
- Write clear, descriptive commit messages
- Update documentation as needed
- Add tests if applicable
- Make sure all existing tests pass

### Reporting Issues

Found a bug or have a feature request? Please open an [issue](https://github.com/thanhcuong1990/Snag/issues) with a clear description.

---

## License

MIT
