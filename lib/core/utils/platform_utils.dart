import 'dart:io' show Directory, Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// True on the desktop targets Inzx ships for (Windows and Linux).
bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// Linux has no embedded web view for the podcast video player.
bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;

/// The app font on desktop. Null leaves the system font, as on Android.
String? get desktopFontFamily => isDesktop ? 'Poppins' : null;

/// A page's background. Desktop pages are see-through, so the album-coloured
/// backdrop behind the whole window shows through them.
Color desktopPageBackground(Color background) =>
    isDesktop ? const Color(0x00000000) : background;

/// Where the app keeps its own data. On mobile the documents directory is
/// private to the app; on desktop it's the user's Documents folder, so data
/// goes in the per-app support directory instead.
Future<Directory> appDataDirectory() => isDesktop
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();
