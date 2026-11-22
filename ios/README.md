# Inzx for iOS

The Flutter app plus a few iOS-only pieces. Everything builds from Windows
through CI; a Mac is only needed to build or debug locally.

## Building

CI (`.github/workflows/ios-build.yml`) builds on every push to
`feat/ios-port` / `main` and attaches an unsigned IPA to published releases:

1. `flutter pub get --enforce-lockfile`
2. `ruby ios/scripts/configure_xcode.rb` — adds what the Flutter template
   doesn't have: the InzxWidget extension, a build phase copying
   `autoeq_targets.json` and the Automix models from
   `android/app/src/main/assets` into `Runner.app/data` (they aren't Flutter
   assets, so the Android build and its Shorebird patches are unaffected),
   and `STRIP_STYLE = non-global` (Automix's C API is found by name over FFI).
   Idempotent; run it once on a Mac before opening `Runner.xcworkspace`.
3. `flutter build ios --release --no-codesign`
4. `scripts/ios/make_ipa.sh` — packages `Payload/Inzx.app`, ad hoc signed
   with each bundle's entitlements so AltStore/SideStore/Sideloadly can
   re-sign it and remap the App Group the widget shares with the app.

The repository secret `ENV_FILE` supplies `.env` (as for the desktop builds).

## What lives where

| Piece | Where |
|---|---|
| Audio tap (equaliser, AutoEQ, loudness), route/volume, folder bookmarks, widget bridge, background-task window | `packages/inzx_ios` (iOS-only plugin) |
| Automix native code: BitChord's analyzer + loop mix (from `android/app/src/main/cpp/native`), desktop's blend renderer and C API (`desktop/automix`), ONNX Runtime | compiled into `inzx_ios` (see `inzx_ios.podspec`) |
| Automix engine (planner, policy, renders) | desktop's Dart engine, `lib/services/automix/desktop` |
| just_audio hooks (each AVPlayerItem announced so the tap can attach) | `packages/just_audio/darwin` |
| Home Screen widgets + playback App Intents | `ios/InzxWidget` |
| YouTube AAC duration fix | `lib/services/playback/youtube_mp4_fix.dart` |

Several approaches follow [BitChord-iOS](https://github.com/maanya145/BitChord-iOS)
(GPL-3.0): AAC-only YouTube formats, the fragmented-MP4 duration fix, the
post-effects processing tap, and sideload packaging.

## Known limits

- No Opus/WebM (AVPlayer can't demux WebM): YouTube is AAC.
- DASH-only and Opus/Vorbis add-on streams are skipped (no DASH in AVPlayer).
- No CarPlay: it needs Apple's CarPlay audio entitlement on a paid account.
- Jams and Inzx Connect stay connected only while audio plays or the app is
  in the foreground; they reconnect on return.
