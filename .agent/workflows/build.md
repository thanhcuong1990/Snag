---
description: how to build the application
---

To verify the build status and catch concurrency errors, run the following command:

// turbo

1. Build the Snag scheme:

```bash
xcodebuild -scheme Snag -project mac/Snag.xcodeproj -configuration Debug
```

Note: If you have multiple destinations (like Mac and iPhone), you might need to specify a destination, for example:

```bash
xcodebuild -scheme Snag -project mac/Snag.xcodeproj -configuration Debug -destination 'platform=macOS'
```
