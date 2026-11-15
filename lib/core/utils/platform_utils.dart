import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'
    show BuildContext, Color, MediaQuery, Theme;
import 'package:path_provider/path_provider.dart';

/// True on the desktop targets Inzx ships for (Windows and Linux).
bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// Linux has no embedded web view for the podcast video player.
bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;

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
