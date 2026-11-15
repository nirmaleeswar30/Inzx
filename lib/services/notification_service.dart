import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../core/utils/platform_utils.dart';
import '../core/l10n/app_localizations_x.dart';
import '../core/providers/locale_provider.dart';
import '../l10n/generated/app_localizations.dart';

/// Service to handle download progress notifications
class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._internal();
  static DownloadNotificationService get instance => _instance;
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  AppLocalizations? _cachedL10n;
  String? _cachedLocaleKey;

  // Notification channel for downloads
  static const String _channelId = 'download_channel';

  // Base notification ID (we'll add track hash to make unique IDs)
  static const int _baseNotificationId = 1000;

  /// The Windows app identity. Must match the installer's Start menu
  /// shortcut and main.cpp's SetCurrentProcessExplicitAppUserModelID, so
  /// toasts are credited to the installed app. The GUID names the toast
  /// activation handler and must never change.
  static const String _windowsAppId = 'Inzx.Inzx';
  static const String _windowsActivatorGuid =
      '22344f20-fbe2-4ea7-8b84-8c42b2a752a3';

  /// Windows shows a progress bar in the download toast and updates it in
  /// place; this is its id inside the toast.
  static const String _windowsProgressId = 'download';

  /// Desktop progress is throttled: the toast or notification is updated
  /// when it has moved this far.
  static const int _desktopProgressStep = 5;
  final Map<int, int> _lastDesktopProgress = {};

  FlutterLocalNotificationsWindows? get _windows => _notifications
      .resolvePlatformSpecificImplementation<FlutterLocalNotificationsWindows>();

  /// The app icon shown in Windows toasts, from the app's own assets.
  static String? _windowsIconPath() {
    if (!Platform.isWindows) return null;
    final dir = File(Platform.resolvedExecutable).parent.path;
    final path = '$dir\\data\\flutter_assets\\assets\\logo_transparent.png';
    return File(path).existsSync() ? path : null;
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;
    final l10n = await _resolveL10n();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Inzx',
        appUserModelId: _windowsAppId,
        guid: _windowsActivatorGuid,
        iconPath: _windowsIconPath(),
      ),
    );

    try {
      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    } catch (e) {
      // No notification service (a Linux desktop without one): downloads
      // still show their progress in the app.
      debugPrint('DownloadNotificationService: unavailable: $e');
      return;
    }

    // Create the notification channel for Android
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          l10n.downloads,
          description: l10n.downloadNotificationsChannelDescription,
          importance: Importance.low, // Low so it doesn't make sound
          showBadge: false,
        ),
      );

      // Request notification permission for Android 13+
      if (Platform.isAndroid) {
        await androidPlugin.requestNotificationsPermission();
      }
    }

    _isInitialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - could open download manager
    debugPrint('Notification tapped: ${response.payload}');
  }

  /// Get unique notification ID for a track
  int _getNotificationId(String trackId) {
    return _baseNotificationId + trackId.hashCode.abs() % 10000;
  }

  /// Show download started notification
  Future<void> showDownloadStarted(String trackId, String trackTitle) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized) return;
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);
    _lastDesktopProgress[notificationId] = 0;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      l10n.downloads,
      channelDescription: l10n.downloadNotificationsChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
      subText: l10n.downloading,
    );

    await _notifications.show(
      id: notificationId,
      title: trackTitle,
      body: l10n.downloadStartingNotification,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        windows: WindowsNotificationDetails(
          progressBars: [
            WindowsProgressBar(
              id: _windowsProgressId,
              status: l10n.downloading,
              value: 0,
              label: '0%',
            ),
          ],
        ),
      ),
      payload: trackId,
    );
  }

  /// Update download progress notification
  Future<void> updateDownloadProgress(
    String trackId,
    String trackTitle,
    double progress,
  ) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized) return;
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);
    final progressPercent = (progress * 100).toInt();

    if (isDesktop) {
      final last = _lastDesktopProgress[notificationId] ?? -100;
      if (progressPercent - last < _desktopProgressStep &&
          progressPercent < 100) {
        return;
      }
      _lastDesktopProgress[notificationId] = progressPercent;
      final windows = _windows;
      if (windows != null) {
        // In place: showing the toast again would pop it up each time.
        await windows.updateProgressBar(
          notificationId: notificationId,
          progressBar: WindowsProgressBar(
            id: _windowsProgressId,
            status: l10n.downloading,
            value: progress.clamp(0.0, 1.0),
            label: '$progressPercent%',
          ),
        );
        return;
      }
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      l10n.downloads,
      channelDescription: l10n.downloadNotificationsChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
      subText: '$progressPercent%',
    );

    await _notifications.show(
      id: notificationId,
      title: trackTitle,
      body: l10n.downloadingProgress(progressPercent),
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: trackId,
    );
  }

  /// Show download completed notification
  Future<void> showDownloadCompleted(String trackId, String trackTitle) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized) return;
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);
    _lastDesktopProgress.remove(notificationId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      l10n.downloads,
      channelDescription: l10n.downloadNotificationsChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    await _notifications.show(
      id: notificationId,
      title: trackTitle,
      body: l10n.downloadCompleteNotification,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        windows: const WindowsNotificationDetails(),
      ),
      payload: trackId,
    );

    // Android clears it after 3 seconds; on desktop it stays in the
    // notification centre like any other.
    if (!isDesktop) {
      Future.delayed(const Duration(seconds: 3), () {
        cancelNotification(trackId);
      });
    }
  }

  /// Show download failed notification
  Future<void> showDownloadFailed(
    String trackId,
    String trackTitle,
    String error,
  ) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized) return;
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);
    _lastDesktopProgress.remove(notificationId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      l10n.downloads,
      channelDescription: l10n.downloadNotificationsChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    await _notifications.show(
      id: notificationId,
      title: trackTitle,
      body: localizeDownloadError(l10n, error),
      notificationDetails: NotificationDetails(
        android: androidDetails,
        windows: const WindowsNotificationDetails(),
      ),
      payload: trackId,
    );
  }

  Future<AppLocalizations> _resolveL10n() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(AppLocaleNotifier.localePrefKey);
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final cacheKey =
        '${storedCode ?? 'system'}|${appLocaleStorageKey(resolveEffectiveAppLocale(systemLocale: systemLocale))}';

    if (_cachedL10n != null && _cachedLocaleKey == cacheKey) {
      return _cachedL10n!;
    }

    final locale = resolveEffectiveAppLocale(
      storedCode: storedCode,
      systemLocale: systemLocale,
    );

    final l10n = lookupAppLocalizations(locale);
    _cachedL10n = l10n;
    _cachedLocaleKey = cacheKey;
    return l10n;
  }

  /// Cancel notification for a track
  Future<void> cancelNotification(String trackId) async {
    final notificationId = _getNotificationId(trackId);
    _lastDesktopProgress.remove(notificationId);
    if (!_isInitialized) return;
    await _notifications.cancel(id: notificationId);
  }

  /// Cancel all download notifications
  Future<void> cancelAllNotifications() async {
    _lastDesktopProgress.clear();
    if (!_isInitialized) return;
    await _notifications.cancelAll();
  }
}
