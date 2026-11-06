import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apps the share sheet can send a card straight to.
enum ShareApp {
  instagram('instagram'),
  snapchat('snapchat');

  const ShareApp(this.wire);

  /// The name the native side and saved preferences know it by.
  final String wire;
}

/// [installed] apps with the most recently used first. Instagram leads until
/// something has been used, then whichever was used last does.
List<ShareApp> orderShareApps({
  required List<String> recent,
  required Set<ShareApp> installed,
}) {
  final ordered = <ShareApp>[];
  for (final wire in recent) {
    for (final app in ShareApp.values) {
      if (app.wire == wire && !ordered.contains(app)) ordered.add(app);
    }
  }
  for (final app in ShareApp.values) {
    if (!ordered.contains(app)) ordered.add(app);
  }
  return ordered.where(installed.contains).toList();
}

/// The native half of the share sheet (`ShareBridge.kt`).
///
/// A build from before that bridge existed can still get this code by OTA
/// patch. Every call then lands on [MissingPluginException], which reads here
/// as "no direct targets": the sheet simply offers Android's share menu.
class NativeShare {
  const NativeShare();

  static const MethodChannel _channel = MethodChannel('inzx/share');

  /// Installed direct targets, or null on a build with no native bridge.
  Future<Set<ShareApp>?> installedApps() async {
    try {
      final wires = await _channel.invokeListMethod<String>('installedTargets');
      return {
        for (final app in ShareApp.values)
          if (wires?.contains(app.wire) ?? false) app,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return const {};
    }
  }

  Future<bool> sendTo(ShareApp app, String imagePath, {String? text}) async {
    try {
      return await _channel.invokeMethod<bool>('shareImage', {
            'target': app.wire,
            'path': imagePath,
            'text': text,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> saveToGallery(String imagePath, String name) async {
    try {
      return await _channel.invokeMethod<bool>('saveImage', {
            'path': imagePath,
            'name': name,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Remembers the sheet's choices between shares.
class SharePreferences {
  const SharePreferences();

  static const _recentKey = 'inzx_share_recent_apps';
  static const _styleKey = 'inzx_share_card_style';
  static const _themeKey = 'inzx_share_card_theme';

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> recentApps() async =>
      (await _prefs())?.getStringList(_recentKey) ?? const [];

  Future<void> markUsed(ShareApp app) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    final recent = prefs.getStringList(_recentKey) ?? const <String>[];
    await prefs.setStringList(_recentKey, [
      app.wire,
      ...recent.where((w) => w != app.wire),
    ]);
  }

  Future<String?> cardStyle() async => (await _prefs())?.getString(_styleKey);
  Future<int?> cardTheme() async => (await _prefs())?.getInt(_themeKey);

  Future<void> saveCardLook(String style, int theme) async {
    final prefs = await _prefs();
    await prefs?.setString(_styleKey, style);
    await prefs?.setInt(_themeKey, theme);
  }
}
