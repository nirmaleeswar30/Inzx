<div align="center">

<img src="assets/icon/logo.png" alt="Nivio Logo" width="200"/>

<h1>Inzx</h1>

**A modern YouTube Music client with dynamic theming and real-time Jam sessions**

[![Flutter](https://img.shields.io/badge/Flutter-3.10.3-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10.3-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Features](#-features) • [Screenshots](#-screenshots) • [Installation](#-installation) • [Build](#-building-from-source) • [Tech Stack](#-tech-stack) • [Contributing](#-contributing)

</div>

---

## ✨ Features

### 🎧 Music Playback
- **YouTube Music Integration** - Stream millions of songs from YouTube Music
- **Offline-First Architecture** - Smart caching for seamless offline playback
- **Background Playback** - Full media controls with notification support
- **Audio Session Management** - Proper audio focus handling
- **Gapless Playback** - Smooth transitions between tracks

### 🎨 Beautiful UI
- **Material Design 3** - Modern, clean interface with dynamic theming
- **Dynamic Colors** - Adaptive colors extracted from album artwork
- **Dark/Light Mode** - Automatic theme switching
- **Smooth Animations** - Fluid transitions and micro-interactions
- **Album Art Visualization** - Stunning now-playing screen with palette-based theming

### 👥 Collaborative Listening (Jams)
- **Real-time Sync** - Listen together with friends in real-time
- **Host & Participant Roles** - Granular permission control
- **Shared Queue** - Collaborative queue management
- **Live Playback Sync** - Automatic position and state synchronization
- **"Last Controller Wins"** - Intelligent conflict resolution for multi-user control

### 📚 Music Library
- **YouTube Music Integration** - Access your YT Music library, playlists, and liked songs
- **Local Files Support** - Play music from device storage
- **Smart Playlists** - Create and manage custom playlists
- **Download Management** - Download tracks for offline playback
- **Search & Discovery** - Powerful search with filters and recommendations

### 🔒 Privacy & Security
- **Offline-First** - Works without internet connection
- **Secure Storage** - Encrypted credentials storage
- **No Tracking** - Your listening habits stay private
- **Optional Cloud Sync** - Choose when to connect

---

## 📱 Screenshots

<div align="center">

| Home | Now Playing | Library | Jams |
|------|-------------|---------|------|
| ![Home](screenshots/home.png) | ![Now Playing](screenshots/now_playing.png) | ![Library](screenshots/library.png) | ![Jams](screenshots/jams.png) |

| Search | Playlist | Folders | Settings |
|--------|----------|-----------|----------|
| ![Search](screenshots/search.png) | ![Playlist](screenshots/playlist.png) | ![Folders](screenshots/folders.png) | ![Settings](screenshots/settings.png) |

</div>

---

## 🚀 Installation

### Download APK
Download the latest release from the [Releases](../../releases) page.

### Install via ADB
```bash
adb install app-release.apk
```

---

## 🛠️ Building from Source

### Prerequisites
- **Flutter SDK** (3.10.3 or higher)
- **Dart SDK** (3.10.3 or higher)
- **Android Studio** or **VS Code** with Flutter extensions
- **Android SDK** (for Android builds)
- **Git**

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/nirmaleeswar30/Inzx.git
   cd Inzx
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run code generation** (for Riverpod providers)
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Configure Environment Variables**
   - Create a `.env` file in the root directory:
     ```bash
     cp .env.example .env
     ```

5. **Configure Supabase** (for Jams feature)
   - Create a Supabase project at [supabase.com](https://supabase.com)
   - Enable Realtime in your Supabase project settings
   - Update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in your `.env` file

6. **Configure Google Sign-In** (for Jams user profiles)
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create a new project or select an existing one
   - Navigate to **APIs & Services > Credentials**
   - Create an **OAuth 2.0 Client ID**:
     - For Android: Select "Android" and add your app's package name and SHA-1 fingerprint
     - For Web (required for Android server auth): Select "Web application"
   - Update `GOOGLE_WEB_CLIENT_ID` in your `.env` file with the **Web Client ID**
   
   > **Note:** The app uses the `google_sign_in` package standalone for basic user profile info in Jams.

6. **Add your app icons and splash screen** (optional)
   - Use 1024x1024 pixel png iages and place them inside assets/icon for custom app icons and assets/splash for custom splash screen during app starts. 
   - Then run the following:
   ```bash
      dart run flutter_launcher_icons 
      dart run flutter_native_splash:create 
   ```   
### Run in Development

```bash
# Run on connected device
flutter run

# Run in release mode
flutter run --release
```

### Build for Production

```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# Build with split APKs per ABI (smaller file sizes)
flutter build apk --split-per-abi --release
```

Output files:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- App Bundle: `build/app/outputs/bundle/release/app-release.aab`

---

## 🏗️ Tech Stack

### Core
- **Flutter** - UI framework
- **Dart** - Programming language
- **Riverpod** - State management with code generation

### Data & Storage
- **Hive** - Fast, lightweight NoSQL database for caching
- **Flutter Secure Storage** - Encrypted credentials storage
- **Supabase** - Real-time backend for Jams feature
- **Shared Preferences** - Local settings storage

### Audio
- **just_audio** - Advanced audio playback
- **audio_service** - Background playback and media controls
- **audio_session** - Audio focus and session management
- **youtube_explode_dart** - YouTube stream extraction

### UI & Design
- **Material Design 3** - Modern design language
- **Iconsax** - Beautiful icon set
- **Cached Network Image** - Optimized image loading
- **Palette Generator** - Dynamic color extraction from artwork

### Features
- **Google Sign-In** - YouTube Music authentication
- **WebView** - YT Music cookie-based login
- **Permission Handler** - Runtime permissions
- **File Picker** - Local file access
- **Share Plus** - Content sharing
- **Flutter Local Notifications** - Download progress notifications

---

## 📁 Project Structure

```
lib/
├── main.dart                      # App entry point
├── core/
│   ├── design_system/             # Reusable UI components
│   ├── layout/                    # Layout templates
│   ├── providers/                 # Core providers
│   ├── router/                    # Navigation
│   ├── services/                  # Core services
│   │   ├── audio_player_service.dart
│   │   ├── supabase_service.dart
│   │   └── ...
│   └── theme/                     # App theming
├── data/
│   ├── entities/                  # Data entities
│   ├── models/                    # Data models
│   ├── repositories/              # Data repositories
│   └── sources/                   # Data sources
├── models/                        # Business models
│   ├── track.dart
│   ├── album_artist_playlist.dart
│   └── ...
├── providers/                     # Feature providers
│   ├── music_providers.dart
│   ├── jams_provider.dart
│   └── ...
├── screens/                       # UI screens
│   ├── tabs/                      # Bottom nav tabs
│   ├── widgets/                   # Screen-specific widgets
│   └── ...
└── services/                      # Feature services
    ├── jams/                      # Jams (collaborative listening)
    │   ├── jams_service_supabase.dart
    │   ├── jams_sync_controller.dart
    │   └── jams_models.dart
    ├── download_service.dart
    └── ...
```

---

## 🎯 Key Features Explained

### Jams (Collaborative Listening)

Jams allows multiple users to listen to music together in real-time with synchronized playback.

**Architecture:**
- **Supabase Realtime** - WebSocket-based real-time communication
- **JamsSyncController** - Bidirectional sync between host and participants
- **Conflict Resolution** - "Last controller wins" strategy
- **Permission System** - Host can grant control to specific participants

**Features:**
- ✅ Real-time playback synchronization (position, play/pause, track changes)
- ✅ Shared queue with drag-to-reorder
- ✅ Auto-fetch radio tracks when queue runs low
- ✅ Multiple controllers with permission-based access
- ✅ Drift correction for perfect sync across devices

### Offline-First Architecture

**Smart Caching Strategy:**
1. Stream audio from YouTube while simultaneously caching
2. Automatically serve from cache on subsequent plays
3. Prioritize cached content when offline
4. Intelligent cache management to optimize storage

**Benefits:**
- Instant playback of frequently played tracks
- Seamless offline experience
- Reduced data usage
- Better battery life

### YouTube Music Integration

**Login Methods:**
1. **Google Sign-In** - Standard OAuth flow
2. **Cookie-based** - WebView login for accounts with 2FA

**Features:**
- Access your YT Music library
- Sync liked songs and playlists
- Get personalized recommendations
- Search entire YT Music catalog

---

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run integration tests
flutter drive --target=test_driver/app.dart
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Write meaningful commit messages
- Add tests for new features
- Update documentation as needed
- Run `dart format .` before committing
- Ensure `flutter analyze` passes

---

## 🐛 Known Issues

- [ ] Splash screen duration may be brief on fast devices
- [ ] Some YT Music features require active internet connection
- [ ] Jams feature requires Supabase configuration

---

## 📝 Roadmap

- [ ] **Crossfade** - Smooth transitions between tracks
- [ ] **Android Auto** - Car integration
- [ ] **Chromecast support** - Cast to speakers
- [ ] **Desktop support** - Windows, macOS, Linux builds
- [ ] **Social features** - Share listening activity
- [ ] **Advanced statistics** - Listening history and insights

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [OuterTune](https://github.com/OuterTune/OuterTune) - Kotlin based client
- [Flutter](https://flutter.dev) - Amazing UI framework
- [just_audio](https://pub.dev/packages/just_audio) - Excellent audio player
- [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) - YouTube stream extraction
- [Supabase](https://supabase.com) - Real-time backend infrastructure
- [Iconsax](https://iconsax.io) - Beautiful icon set

---

## 📧 Contact

Have questions or suggestions? Feel free to:
- Open an [issue](../../issues)
- Start a [discussion](../../discussions)
- Reach out on social media

---

<div align="center">

**Made with ❤️ and Flutter**

⭐ Star this repo if you like it!

</div>
