<div align="center">
	<img src="assets/icon/logo_transparent.png" alt="Inzx Logo" width="200"/>
<h1>Inzx</h1>

*A modern YouTube Music client with dynamic theming, word-level synced lyrics, and real-time Jam sessions*

[![Flutter](https://img.shields.io/badge/Flutter-3.10.3-AF94F5?style=for-the-badge&logo=flutter&logoColor=white&labelColor=0d1117)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10.3-AF94F5?style=for-the-badge&logo=dart&logoColor=white&labelColor=0d1117)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-AF94F5?style=for-the-badge&labelColor=0d1117)](LICENSE)


[Features](#features) • [Screenshots](#screenshots) • [Development](./DEVELOPMENT.md) • [Contributing](./CONTRIBUTING.md)


</div>

> [!WARNING]
> Inzx is only available on the platforms listed here and not available on the Play Store or any other site. Any future platforms will be announced here. 
> 
> Please avoid installing unofficial or modified versions of the app for your own safety.

<div align="center">

[<img src="assets/badge-obtainium.png" alt="Obtainium" height="40">](https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/nirmaleeswar30/Inzx/)⠀
[<img src="assets/badge-github.png" alt="Get it on GitHub" height="40">](https://github.com/nirmaleeswar30/Inzx/releases/latest)⠀⠀

</div>

## ❤️ Sponsors

If you enjoy using Inzx, consider supporting the development!
Your support helps keep the project alive and actively maintained.

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-%23ea4aaa?style=for-the-badge&logo=github)](https://github.com/sponsors/nirmaleeswar30)

## Features

#### 🎧 Playback
- Stream millions of songs, playlists, albums, and artists via YouTube Music
- Background playback with full media notifications and Android Auto support
- Download & cache tracks for offline use
- Gapless playback with stream prefetching for 0ms latency
- Seamless audio focus, phone call handling, and crossfade support

#### 🎨 UI & Design
- App-wide dynamic theming that adapts to the currently playing album's cover art
- Multiple Now Playing screen styles (full-screen album art, cover view, ripple view) with choice of wavy, normal, or spectrum seekbars
- Live word-level synced karaoke lyrics from BetterLyrics, LRCLib, YouTube Captions, and Genius
- Localized app UI with locale-aware YouTube Music content, supporting 19+ languages
  
#### 📚 Library & Account
- Local file scanning and playback
- Sync saved playlists, liked songs, albums, and subscribed artists
- Custom local playlist creation, management, and drag-to-reorder queue editing

#### 👥 Collaborative Listening (Jams)
- Listen together with friends in real-time
- Host & participant roles with granular permission control
- Shared, collaboratively editable queue with drift-corrected playback sync

#### 🔒 Privacy & Security
- Fully functional without continuous network connectivity
- Encrypted local credential storage
- No analytics tracking

## Screenshots

<div align="center">

| **Home** | **Now Playing** | **Library** | **Jams** |
|:---:|:---:|:---:|:---:|
| ![Home](./.github/screenshots/home.png) | ![Now Playing](./.github/screenshots/nowplaying.gif) | ![Library](./.github/screenshots/library.png) | ![Jams](./.github/screenshots/jam.png) |
| **Search** | **Playlist** | **Folders** | **Lyrics** |
| ![Search](./.github/screenshots/search.png) | ![Playlist](./.github/screenshots/playlist.png) | ![Folders](./.github/screenshots/folders.png) | ![Lyrics](./.github/screenshots/lyrics.png) |

</div>

<table width="100%">
<tr>
<th align="center">Better Lyrics</th>
</tr>
<tr>
<td align="center"><img src="./.github/screenshots/output.gif" width="100%"></td>
</tr>
</table>

</div>

<details open>
<summary>Alternative Styles</summary>

#### Now Playing Screen
<table>
<tr>
<th align="center" width="33%">Default</th>
<th align="center" width="33%">Cinematic</th>
<th align="center" width="33%">Ripple</th>
</tr>
<tr>
<td width="33%"><img src="./.github/screenshots/player-default.png" width="100%"></td>
<td width="33%"><img src="./.github/screenshots/player-cinematic.png" width="100%"></td>
<td width="33%"><img src="./.github/screenshots/player-ripple.png" width="100%"></td>
</tr>
</table>

#### Seekbar Styles
<table>
<tr>
<th align="center" width="33%">Default</th>
<th align="center" width="33%">Waveform</th>
<th align="center" width="33%">Spectrum</th>
</tr>
<tr>
<td width="33%"><img src="./.github/screenshots/seekbar-default.png" width="100%"></td>
<td width="33%"><img src="./.github/screenshots/seekbar-waveform.png" width="100%"></td>
<td width="33%"><img src="./.github/screenshots/waveform-spectrum.png" width="100%"></td>
</tr>
</table>

</details>

<details open>
<summary>More Screenshots</summary>

<div align="center">

| **Widget 4x1** | **Widget 4x2** |
|:---:|:---:|
| ![Widget 4x1](./.github/screenshots/widget-4x1.png) | ![Widget 4x2](./.github/screenshots/widget-4x2.png) |

| **Android Auto** | **Android Auto - Now Playing** |
|:---:|:---:|
| ![Android Auto](./.github/screenshots/android_auto.png) | ![Android Auto - Now Playing](./.github/screenshots/android_auto-nowplaying.png) |

</div>
</details>

---

## Multi-language Support

Inzx supports localized app UI and locale-aware YouTube Music content requests.

**Supported languages:**
English, Turkish, Russian, Hindi, Malayalam, Tamil, Kannada, Telugu, Spanish, Portuguese (Brazil), French, German, Indonesian, Japanese, Korean, Arabic, Ukrainian, Thai, Simplified Chinese, Traditional Chinese.

---

## Roadmap

- [x] **Crossfade** — Smooth transitions between tracks
- [x] **Android Auto** — Dashboard car integration
- [x] **Skeleton Loaders** — App-wide Skeletonizer loading placeholders
- [x] **Word-Level Synced Lyrics** — BetterLyrics TTML karaoke engine
- [ ] **Chromecast support** — Cast playback to external speakers
- [ ] **Desktop support** — Windows, macOS, Linux desktop targets

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) to see how you can help out!

## Acknowledgments

- [OuterTune](https://github.com/OuterTune/OuterTune) — Kotlin music client design reference
- [Flutter](https://flutter.dev) — UI framework
- [just_audio](https://pub.dev/packages/just_audio) — Audio player package
- [Supabase](https://supabase.com) — Real-time infrastructure
- [BetterLyrics](https://github.com/nirmaleeswar30/Inzx) — Word-level synced lyrics API


## Star History

<a href="https://www.star-history.com/?repos=nirmaleeswar30%2Finzx&type=timeline&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=nirmaleeswar30/inzx&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=nirmaleeswar30/inzx&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=nirmaleeswar30/inzx&type=date&legend=top-left" />
 </picture>
</a>

## License

This project is licensed under the [MIT License](LICENSE).
