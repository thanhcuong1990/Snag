# react-native-snag

React Native wrapper for the Snag network debugger.

> [!NOTE]
> This library is **optional**. Snag native libraries now support **truly zero-config** React Native logging and network interception. Use this library if you need manual tagging or object inspection.

## Installation

```bash
npm install react-native-snag
```

> [!TIP]
> On Android, we recommend using `debugImplementation` in your `android/app/build.gradle` (see below) to ensure the library is excluded from production builds.

## Integration

### iOS

Zero configuration required. Snag automatically:
- Initializes itself on app startup (in debug builds).
- Intercepts and debugs network requests.

### Android

Zero configuration required. Snag automatically:
- Initializes itself on app startup.
- Intercepts all React Native network requests.
- Captures standard Android logs.

## Production Safety (Zero-Config)

Snag is designed to be **safe by default** in production. You don't need to write any extra code to "ignore" it for release builds.

### Internal Guards
1.  **Android**: Automatically detects the environment. If the app is not debuggable and not on an emulator, Snag remains inactive unless `com.snag.ENABLED` is set to `true` in your `AndroidManifest.xml`.
2.  **iOS**: Native initialization normally only runs in `#DEBUG`. You can force-enable it by adding `SnagEnabled` (Boolean) to your `Info.plist` or passing `-SnagEnabled` as a launch argument.
3.  **JavaScript**: All logging calls check if Snag is natively enabled. If force-enabled in production, JS logs will pass through.

### Advanced: Complete Binary Removal
If you want to completely remove the library native binaries from your production build (to save space), use these native configuration steps.

> [!CAUTION]
> If you remove the binaries for production builds, the **Force-Enable** feature (via `Info.plist` or `Manifest`) will **not work** because the code is physically removed from the app.

- **Android**: Use `debugImplementation` in `app/build.gradle`.
- **iOS**: Use `:configurations => ['Debug']` in your `Podfile`.

---

## Usage

```tsx
import Snag from 'react-native-snag';

// Capture a custom log with a tag
Snag.log('App Started', 'info', 'Lifecycle');

// Advanced: Manual Console Hijacking
// Only needed if you want to inspect complex objects via console.log
// (Standard string logs are already captured natively via zero-config)
Snag.hijackConsole();
```

## Captured Logs on Snag Mac App
All logs captured via `Snag.log` will appear in the Snag Mac App when the device is connected to the same network.
