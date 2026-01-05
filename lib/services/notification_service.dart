import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

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

  // Notification channel for downloads
  static const String _channelId = 'download_channel';
  static const String _channelName = 'Downloads';
  static const String _channelDescription = 'Download progress notifications';

  // Base notification ID (we'll add track hash to make unique IDs)
  static const int _baseNotificationId = 1000;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

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
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
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

    final notificationId = _getNotificationId(trackId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
      subText: 'Downloading',
    );

    await _notifications.show(
      notificationId,
      trackTitle,
      'Starting download...',
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

    final notificationId = _getNotificationId(trackId);
    final progressPercent = (progress * 100).toInt();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
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
      'Downloading...',
      NotificationDetails(android: androidDetails),
      payload: trackId,
    );
  }

  /// Show download completed notification
  Future<void> showDownloadCompleted(String trackId, String trackTitle) async {
    if (!_isInitialized) await initialize();

    final notificationId = _getNotificationId(trackId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    await _notifications.show(
      notificationId,
      trackTitle,
      'Download complete',
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

    final notificationId = _getNotificationId(trackId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    await _notifications.show(
      notificationId,
      trackTitle,
      'Download failed: $error',
      NotificationDetails(android: androidDetails),
      payload: trackId,
    );
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
