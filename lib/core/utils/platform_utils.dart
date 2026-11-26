import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart'
    show BuildContext, Color, MediaQuery, Theme;
import 'package:path_provider/path_provider.dart';

/// True on the desktop targets Inzx ships for (Windows and Linux).
bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// Linux has no embedded web view for the podcast video player.
bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;

/// iPhone and iPad.
bool get isIOS => !kIsWeb && Platform.isIOS;

/// Where the equaliser, AutoEQ and loudness normalization are worked out in
/// Dart (DesktopAutoEq, EqChain, DesktopLoudness) and applied by a native
/// stage: libmpv's filters on desktop, the audio tap on iOS. Android runs
/// its own Kotlin versions in ExoPlayer.
bool get usesDartAudioDsp => isDesktop || isIOS;

/// Whether the audio engine can play Opus/WebM. AVPlayer can't demux WebM,
/// so on iOS every YouTube stream and download is AAC (M4A).
bool get canPlayOpus => !isIOS;

/// iOS moves an app's container on every update (and sideloaders' re-signs),
/// so a saved absolute path like
/// `/var/mobile/Containers/Data/Application/<old-uuid>/Documents/x.m4a`
/// points nowhere afterwards. This rebases any such path onto the current
/// container; other paths, and other platforms, come back unchanged.
String resolveAppPath(String path) {
  if (!isIOS) return path;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return path;
  return rebaseContainerPath(path, home);
}

/// [path] moved from whichever app container it was saved in to [home], the
/// current one; unchanged when it isn't inside an app container.
String rebaseContainerPath(String path, String home) {
  if (path.startsWith(home)) return path;
  final match = _containerPrefix.firstMatch(path);
  if (match == null) return path;
  return '$home${path.substring(match.end)}';
}

final _containerPrefix = RegExp(
  r'^(?:/private)?/.*?/Containers/Data/Application/[0-9A-Fa-f-]{36}',
);

/// Columns for a grid of square cards: two on phones, as many as fit on desktop.
int desktopGridColumns(BuildContext context) {
  if (!isDesktop) return 2;
  return (MediaQuery.sizeOf(context).width / 180).floor().clamp(2, 10);
}

/// The app font on desktop. Null leaves the system font, as on Android.
String? get desktopFontFamily => isDesktop ? 'Poppins' : null;

/// Universal font fallback chain for desktop.
/// Allows Linux and Windows to resolve any world script glyphs (Indic, CJK,
/// Southeast Asian, Arabic, Cyrillic, Emojis) seamlessly.
List<String>? get desktopFontFamilyFallback => isDesktop
    ? const [
        // Standard system sans
        'Noto Sans',
        'DejaVu Sans',
        'FreeSans',
        'Ubuntu',

        // East Asian (CJK)
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'Noto Sans CJK JP',
        'Noto Sans CJK KR',
        'NotoSansCJKsc',
        'NotoSansCJKtc',
        'NotoSansCJKjp',
        'NotoSansCJKkr',
        'NotoSansCJKSC',
        'NotoSansCJKTC',
        'NotoSansCJKJP',
        'NotoSansCJKKR',
        'WenQuanYi Micro Hei',
        'WenQuanYi Zen Hei',
        'Droid Sans Fallback',

        // South Asian (Indic)
        'Noto Sans Tamil',
        'NotoSansTamil',
        'Noto Sans Devanagari',
        'NotoSansDevanagari',
        'Noto Sans Telugu',
        'NotoSansTelugu',
        'Noto Sans Malayalam',
        'NotoSansMalayalam',
        'Noto Sans Kannada',
        'NotoSansKannada',
        'Noto Sans Bengali',
        'NotoSansBengali',
        'Noto Sans Gujarati',
        'NotoSansGujarati',
        'Noto Sans Gurmukhi',
        'NotoSansGurmukhi',
        'Noto Sans Oriya',
        'NotoSansOriya',
        'Noto Sans Sinhala',
        'NotoSansSinhala',
        'Lohit Tamil',
        'Lohit Devanagari',

        // Southeast Asian
        'Noto Sans Thai',
        'Noto Sans Myanmar',
        'Noto Sans Khmer',
        'Noto Sans Lao',

        // Middle Eastern
        'Noto Sans Arabic',
        'Noto Sans Hebrew',

        // Others
        'Noto Sans Georgian',
        'Noto Sans Armenian',
        'Noto Sans Ethiopic',

        // Emojis
        'Noto Color Emoji',
        'Segoe UI Emoji',
      ]
    : null;

/// A page's background. Desktop pages are see-through, so the album-coloured
/// backdrop behind the whole window shows through them.
Color desktopPageBackground(Color background) =>
    isDesktop ? const Color(0x00000000) : background;

/// Keeps sheet content opaque over the desktop page backdrop.
Color modalSheetBackground(BuildContext context, [Color? background]) {
  final theme = Theme.of(context);
  return isDesktop
      ? (background ?? theme.colorScheme.surface).withValues(alpha: 1)
      : background ?? theme.scaffoldBackgroundColor;
}

/// Where the app keeps its own data. On mobile the documents directory is
/// private to the app; on desktop it's the user's Documents folder, so data
/// goes in the per-app support directory instead.
Future<Directory> appDataDirectory() => isDesktop
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();
