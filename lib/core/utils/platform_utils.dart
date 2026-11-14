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
