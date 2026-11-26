## Inzx fork

flutter_inappwebview_android 1.1.3 (the latest stable release, from 2024) with one change: `android/build.gradle` uses `getDefaultProguardFile('proguard-android-optimize.txt')` instead of `'proguard-android.txt'`, which Android Gradle Plugin 9 (required by Flutter 3.50) refuses to build. Drop this copy once a stable release builds on AGP 9.

# flutter\_inappwebview\_android

The Android WebView implementation of [`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview).

## Usage

This package is [endorsed](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin),
which means you can simply use `flutter_inappwebview`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.