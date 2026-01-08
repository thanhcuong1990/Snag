# react-native-snag

React Native wrapper for the Snag network debugger.

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
1.  **Android**: Automatically detects the environment. If the app is not debuggable and not on an emulator, Snag remains inactive.
2.  **iOS**: Native initialization is wrapped in `#if DEBUG`, ensuring it only runs in development.
3.  **JavaScript**: All logging calls are internally wrapped in `__DEV__` checks, so they are ignored in your production JS bundle.

### Advanced: Complete Binary Removal
If you want to completely remove the library binaries from your production build (to save space), you can optionally use these native configuration steps:

- **Android**: Use `debugImplementation` in `app/build.gradle`.
- **iOS**: Use `:configurations => ['Debug']` in your `Podfile`.

---

## Usage

```tsx
import Snag from 'react-native-snag';

// Capture a custom log
Snag.log('User clicked login button');
```

## captured Logs on Snag Mac App
All logs captured via `Snag.log` will appear in the Snag Mac App when the device is connected to the same network.
