import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui' as ui;
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

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;
    final l10n = await _resolveL10n();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

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
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);

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
      notificationId,
      trackTitle,
      l10n.downloadStartingNotification,
      NotificationDetails(android: androidDetails),
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
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);
    final progressPercent = (progress * 100).toInt();

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
      notificationId,
      trackTitle,
      l10n.downloadingProgress(progressPercent),
      NotificationDetails(android: androidDetails),
      payload: trackId,
    );
  }

  /// Show download completed notification
  Future<void> showDownloadCompleted(String trackId, String trackTitle) async {
    if (!_isInitialized) await initialize();
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);

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
      notificationId,
      trackTitle,
      l10n.downloadCompleteNotification,
      NotificationDetails(android: androidDetails),
      payload: trackId,
    );

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      cancelNotification(trackId);
    });
  }

  /// Show download failed notification
  Future<void> showDownloadFailed(
    String trackId,
    String trackTitle,
    String error,
  ) async {
    if (!_isInitialized) await initialize();
    final l10n = await _resolveL10n();

    final notificationId = _getNotificationId(trackId);

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
      notificationId,
      trackTitle,
      localizeDownloadError(l10n, error),
      NotificationDetails(android: androidDetails),
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
    await _notifications.cancel(notificationId);
  }

  /// Cancel all download notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
