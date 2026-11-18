import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/cache/hive_service.dart';
import '../../core/utils/platform_utils.dart';
import 'ios_audio_dsp.dart';
import 'ios_native.dart';
import 'ipad_share.dart';

/// iOS start-up, after Hive is open (main.dart).
Future<void> initIosPlatform() async {
  await IosNative.init();
  IpadAnchoredShare.install();
  await _restoreMusicFolders();
  await _ensureMusicFolder();
  unawaited(IosAudioDsp.instance.start());
}

/// Folders picked outside the app (On My iPhone, iCloud Drive) are only
/// readable once their saved bookmarks are reopened, every launch. Folders
/// inside the app's own container moved with the last update and are
/// rebased; either way the saved list is brought up to date.
Future<void> _restoreMusicFolders() async {
  final moved = {for (final m in await IosNative.restoreFolders()) m.from: m.to};
  try {
    final box = HiveService.localMusicFoldersBox;
    final current = box.values.toList();
    final updated = [
      for (final path in current) moved[path] ?? resolveAppPath(path),
    ];
    if (!listEquals(current, updated)) {
      await box.clear();
      await box.putAll({for (final p in updated) p: p});
    }
  } catch (e) {
    debugPrint('initIosPlatform: folder restore failed: $e');
  }
}

/// Documents/Music, which the Files app shows as On My iPhone > Inzx > Music:
/// the simplest place to put your own files. Added to the library once, on
/// the first launch; removing it from the library afterwards sticks.
Future<void> _ensureMusicFolder() async {
  const flag = 'ios_music_folder_added';
  try {
    final docs = await getApplicationDocumentsDirectory();
    final music = Directory('${docs.path}/Music');
    if (!await music.exists()) await music.create(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flag) ?? false) return;
    final box = HiveService.localMusicFoldersBox;
    if (!box.values.contains(music.path)) await box.put(music.path, music.path);
    await prefs.setBool(flag, true);
  } catch (e) {
    debugPrint('initIosPlatform: music folder setup failed: $e');
  }
}
