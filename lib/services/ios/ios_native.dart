import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iOS-only calls into packages/inzx_ios (InzxIosPlugin.swift). Every
/// call is a no-op elsewhere, so callers only check the platform where the
/// behaviour itself differs.
abstract final class IosNative {
  static const _ios = MethodChannel('inzx/ios');
  static const _dsp = MethodChannel('inzx/ios_dsp');

  /// Output route changes: `{key, label, formFactor}` or null.
  static const routeEvents = EventChannel('inzx/ios_route');

  /// Keeps a file or folder out of iCloud and device backups (downloads and
  /// caches are re-fetchable, and a music library would fill the user's
  /// iCloud).
  static Future<void> excludeFromBackup(String path) async {
    try {
      await _ios.invokeMethod('excludeFromBackup', {'path': path});
    } catch (e) {
      debugPrint('IosNative: excludeFromBackup failed: $e');
    }
  }

  /// Opens the system folder picker. The picked folder stays readable across
  /// launches (it's saved as a bookmark and reopened by [restoreFolders]).
  static Future<String?> pickFolder() async {
    try {
      return await _ios.invokeMethod<String>('pickFolder');
    } catch (e) {
      debugPrint('IosNative: pickFolder failed: $e');
      return null;
    }
  }

  /// Reopens every picked folder. Returns where each saved one is now, for
  /// the ones whose path changed.
  static Future<List<({String from, String to})>> restoreFolders() async {
    try {
      final rows = await _ios.invokeListMethod<Map>('restoreFolders') ?? const [];
      return [
        for (final r in rows)
          (from: r['from'] as String, to: r['to'] as String),
      ];
    } catch (e) {
      debugPrint('IosNative: restoreFolders failed: $e');
      return const [];
    }
  }

  static Future<void> forgetFolder(String path) async {
    try {
      await _ios.invokeMethod('forgetFolder', {'path': path});
    } catch (_) {}
  }

  /// Asks iOS for up to [time] of background running (an app that stopped
  /// playing is otherwise suspended within seconds), e.g. while the next
  /// song resolves after one ended.
  static Future<void> holdBackgroundTime(Duration time) async {
    try {
      await _ios.invokeMethod('holdBackgroundTime', {'seconds': time.inSeconds});
    } catch (_) {}
  }

  static bool _isPad = false;

  /// An iPad (some sheets need an anchor there). Known after [init].
  static bool get isPad => _isPad;

  static Future<void> init() async {
    try {
      _isPad = await _ios.invokeMethod<bool>('isPad') ?? false;
    } catch (_) {}
  }

  // ---- Audio tap ----------------------------------------------------------

  static Future<void> setDspChain(double preampDb, List<Map<String, Object>> filters) async {
    try {
      await _dsp.invokeMethod('setChain', {'preampDb': preampDb, 'filters': filters});
    } catch (e) {
      debugPrint('IosNative: setChain failed: $e');
    }
  }

  static Future<void> setTrackGain(String playerId, double gain) async {
    try {
      await _dsp.invokeMethod('setTrackGain', {'playerId': playerId, 'gain': gain});
    } catch (_) {}
  }
}
