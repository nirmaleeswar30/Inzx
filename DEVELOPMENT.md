# Development

> [!NOTE]
> New to the project? Check out the [open issues](https://github.com/nirmaleeswar30/inzx/issues) — they're a great starting point if you're looking for something to work on.

> [!IMPORTANT]
> Please read [CONTRIBUTING.md](CONTRIBUTING.md) before starting work. It covers contribution guidelines and other ways you can help out beyond code.

## Building from Source

### 1. Check the Prerequisites

* Flutter SDK (3.10.3 or higher)
* Dart SDK (3.10.3 or higher)
* Android Studio or VS Code with Flutter extensions
* Android SDK (for Android builds)
* Git

### 2. Clone the Repository

```bash
git clone https://github.com/nirmaleeswar30/Inzx.git
cd Inzx
```

### 3. Install Dependencies

```bash
flutter pub get
```

### 4. Run Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

### 5. Configure Environment Variables

Copy the example env file to create your own local config:

```bash
cp .env.example .env
```

Then fill in the following values in `.env`:

| Variable | Used For | Where to Get It |
| --- | --- | --- |
| `SUPABASE_URL` | Jams (real-time sync) | [Supabase](https://supabase.com) project settings |
| `SUPABASE_ANON_KEY` | Jams (real-time sync) | [Supabase](https://supabase.com) project settings |
| `GOOGLE_WEB_CLIENT_ID` | Jams user profiles (Google Sign-In) | Google Cloud Console → OAuth 2.0 Web Client ID |

> [!TIP]
> For Supabase, make sure **Realtime** is enabled in your project settings — Jams relies on it for live sync.

### 6. Build Commands

```bash
# Run in debug mode
flutter run

# Build release APK
flutter build apk --release

# Build split APKs per ABI
flutter build apk --split-per-abi --release
```

## Architecture & Tech Stack

### 🏗️ Tech Stack

#### Core Framework

* Flutter — UI framework
* Dart — Language
* Riverpod — State management with code generation

#### Data & Storage

* Hive — Fast NoSQL database for local caching of tracks, playlists, and colors
* Flutter Secure Storage — Encrypted storage for credentials
* Supabase — Real-time WebSockets backend for Jams
* Shared Preferences — App configuration & settings

#### Audio & InnerTube API

* InnerTube API Engine — Direct API integration for YouTube Music catalog, playback streams, shelves, and metadata
* just_audio — Audio player engine with buffering and stream caching
* audio_service — Background media controls & notification integration
* audio_session — Audio focus management

#### UI & Design System

* Skeletonizer — Automatic shimmer skeleton loaders across all screens
* AlbumColorExtractor — Fast 0ms isolate-based palette color extraction
* Iconsax — Icon set
* Cached Network Image — Image caching & management
* Marquee — Scrolling text for long titles
