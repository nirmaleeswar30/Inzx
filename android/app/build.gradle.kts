plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.serialization")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nirmal.inzx"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nirmal.inzx"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Automix native analysis + loop mix (ported from BitChord).
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // The Automix models are read straight out of the APK; leave them
    // uncompressed so that's a plain read, not an inflate.
    androidResources {
        noCompress += listOf("onnx")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.appcompat:appcompat:1.6.1")
    // MediaBrowserCompat for widget Like / Shuffle (talks to audio_service)
    implementation("androidx.media:media:1.7.0")
    // Inzx's ExoPlayer renderers (hi-res + bit-perfect sink, see
    // audio/InzxAudioOutput.kt). Same version the plugins resolve to at
    // runtime (pinned for every module in the root build file).
    implementation("androidx.media3:media3-exoplayer:1.11.0")
    // Automix (ported from BitChord): beat and vocal models, analysis
    // storage, and the coroutines its analysis runs on.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.28.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // AutoEQ (ported from LastWave) keeps its profiles in DataStore.
    implementation("androidx.datastore:datastore-preferences:1.1.7")
}

flutter {
    source = "../.."
}
