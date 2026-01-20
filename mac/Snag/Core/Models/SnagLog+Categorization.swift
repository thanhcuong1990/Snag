import Foundation

extension SnagLog {
    
    enum Category: String, CaseIterable {
        case rn = "React Native"
        case system = "System"
        case app = "App"
        case other = "Other"
    }
    
    func getCategory(detectedAppTag: String?) -> Category {
        guard let tag = self.tag else { return .system }
        
        if tag.starts(with: "com.facebook.react.log") || tag == "React Native" {
            return .rn
        }
        
        if let appTag = detectedAppTag, tag == appTag {
            return .app
        }
        
        if SnagLog.isSystemTag(tag) {
            return .system
        }
        
        return .other
    }
    
    static func isSystemTag(_ tag: String) -> Bool {
        if tag.isEmpty || tag == "System" || tag == "logcat" || tag == "unknown" { return true }
        
        let lowerTag = tag.lowercased()
        
        // Match common system prefixes/patterns
        if lowerTag.starts(with: "android.") || 
           lowerTag.starts(with: "com.android.") ||
           lowerTag.starts(with: "com.google.") ||
           lowerTag.starts(with: "com.apple.") ||
           lowerTag.starts(with: "libc") ||
           lowerTag.starts(with: "art") ||
           lowerTag.starts(with: "gralloc") ||
           lowerTag.starts(with: "egl_") ||
           lowerTag.contains("emulator") ||
           lowerTag.contains("vulkan") {
            return true
        }
        
        // Match specific patterns often seen in logs
        if tag.starts(with: "cr_") || tag.starts(with: "VRI[") || tag.starts(with: "Netd") || tag.contains("Compatibility") {
            return true
        }
        
        return androidSystemTags.contains(tag) || androidSystemTags.contains(lowerTag)
    }

    private static let androidSystemTags: Set<String> = [
        "ApplicationLoaders", "HWUI", "ProfileInstaller", "chromium",
        "Choreographer", "ActivityThread", "ViewRootImpl", "WindowManager",
        "InputMethodManager", "AudioTrack", "OpenGLRenderer", "vndksupport",
        "ServiceManager", "System.out", "System.err",
        "DesktopExperienceFlags", "DesktopModeFlags", "GFXSTREAM",
        "GraphicsEnvironment", "ImeTracker", "InsetsController",
        "ResourcesManager", "SoLoader", "WebViewFactory",
        "WindowOnBackDispatcher", "Zygote", "ashmem",
        "jni_lib_merge", "nativeloader", "Process",
        "StudioAgent", "TransportManager", "SurfaceControl",
        "SurfaceFlavor", "InputTransport", "HostConnection",
        "FrameEvents", "Chatty", "TetheringManager", "BatteryService"
    ]
}
