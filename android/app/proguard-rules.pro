# ==============================================================================
# Hermes Mobile - R8 / ProGuard Optimization & Keep Rules
# ==============================================================================

# 1. Flutter Engine Core & Plugins Registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# 2. Native Application Entry & Platform Channels
-keep class com.example.hermes_mobile.MainActivity { *; }

# 3. AndroidX & Jetpack Components
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.app.NotificationCompat** { *; }
-keep class androidx.core.app.NotificationManagerCompat { *; }
-keep class androidx.lifecycle.DefaultLifecycleObserver { *; }

# 4. Security & Cryptography (used by flutter_secure_storage / Keystore)
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn androidx.security.crypto.**

# 5. Shared Preferences & Local Storage
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# 6. Preserved attributes for reflection, debugging & annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable

# 7. Native JNI Method Callers
-keepclasseswithmembers class * {
    native <methods>;
}

# 8. WebSockets & Network Warning Suppressions
-dontwarn okio.**
-dontwarn java.awt.**
-dontwarn javax.annotation.**
