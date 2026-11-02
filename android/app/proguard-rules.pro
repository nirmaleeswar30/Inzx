# Flutter wrapper
-keep class io.flutter.** { *; }

# ONNX Runtime (Required by libonnxruntime4j_jni.so)
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# BitChord Automix & Native C++ JNI
-keep class com.music.bitchord.** { *; }
-keepclassmembers class com.music.bitchord.** {
    native <methods>;
    *;
}

# AutoEQ / LastWave
-keep class com.lastwave.app.** { *; }
-keepclassmembers class com.lastwave.app.** {
    native <methods>;
    *;
}

# Inzx Audio & UI
-keep class com.inzx.inzx.** { *; }
-keepclassmembers class com.inzx.inzx.** {
    native <methods>;
    *;
}

# Kotlin Coroutines & Serialization
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
    @kotlinx.serialization.SerialName <fields>;
}
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class * implements kotlinx.serialization.KSerializer {
    *;
}
-keepclassmembers class * {
    companion object;
}
-keepattributes *Annotation*,InnerClasses,EnclosingMethod,Signature

# AndroidX Media3 / ExoPlayer
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
