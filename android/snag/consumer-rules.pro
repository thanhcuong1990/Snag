-keep class com.snag.Snag {
    public static void start(android.content.Context);
    public static void start(android.content.Context, com.snag.core.config.Config);
}

-keep class com.snag.SnagInterceptor {
    public static com.snag.SnagInterceptor getInstance();
}

-keep class com.snag.core.config.Config { *; }
-keep class com.snag.models.** { *; }

# React Native is a compileOnly dependency and is resolved reflectively at
# runtime, so consumers without it on the classpath must not fail R8 on it.
-dontwarn com.facebook.react.**
