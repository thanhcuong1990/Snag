-keep class com.snag.Snag {
    public static void start(android.content.Context);
    public static void start(android.content.Context, com.snag.core.config.Config);
}

-keep class com.snag.SnagInterceptor {
    public static com.snag.SnagInterceptor getInstance();
}

-keep class com.snag.core.config.Config { *; }
-keep class com.snag.models.** { *; }
