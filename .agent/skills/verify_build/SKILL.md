---
name: verify_build
description: Verify the build status of the Snag project across all platforms (Mac, iOS, Android).
---

# Verify Build

Use this skill to verify that your changes haven't broken the build for any platform.

## 1. Mac App

Build the Mac application using `xcodebuild`.

```bash
xcodebuild -scheme Snag -project mac/Snag.xcodeproj -configuration Debug -destination 'platform=macOS'
```

## 2. iOS Example App

Build the iOS example application.

```bash
xcodebuild -workspace example/ios/SnagExample.xcworkspace -scheme SnagExample -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 3. Android Example App

Build the Android example application.

```bash
cd example/android && ./gradlew assembleDebug
```
