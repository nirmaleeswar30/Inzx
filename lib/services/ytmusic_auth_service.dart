import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'ytmusic_api_service.dart';

/// Manages YouTube Music authentication state and cookie persistence
class YTMusicAuthService {
  static const String _cookiesKey = 'ytmusic_cookies';
  static const String _accountInfoKey = 'ytmusic_account_info';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final InnerTubeService _innerTubeService;

  Map<String, String> _cookies = {};
  YTMusicAccount? _account;

  YTMusicAuthService(this._innerTubeService);

  /// Whether the user is logged in
  bool get isLoggedIn =>
      _cookies.isNotEmpty && _innerTubeService.isAuthenticated;

  /// Current account info
  YTMusicAccount? get account => _account;

  /// Initialize auth from stored cookies
  Future<bool> initialize() async {
    try {
      final cookiesJson = await _secureStorage.read(key: _cookiesKey);
      if (cookiesJson != null) {
        _cookies = Map<String, String>.from(jsonDecode(cookiesJson));
        _innerTubeService.setAuthCookies(_cookies);

        // Load account info
        final accountJson = await _secureStorage.read(key: _accountInfoKey);
        if (accountJson != null) {
          _account = YTMusicAccount.fromJson(jsonDecode(accountJson));
        }

        // Verify cookies are still valid by making a test request
        final likedSongs = await _innerTubeService.getLikedSongs();
        if (likedSongs.isEmpty) {
          // Cookies may be expired, but don't clear yet - user might have no liked songs
          return true;
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) {print('Failed to initialize YTMusic auth: $e');}
    }
    return false;
  }

  /// Quickly restore auth from cache (for app startup)
  /// This is faster than initialize() as it doesn't verify cookies are still valid
  Future<bool> restoreCachedAuth() async {
    try {
      final cookiesJson = await _secureStorage.read(key: _cookiesKey);
      if (cookiesJson != null) {
        _cookies = Map<String, String>.from(jsonDecode(cookiesJson));
        _innerTubeService.setAuthCookies(_cookies);

        // Load account info
        final accountJson = await _secureStorage.read(key: _accountInfoKey);
        if (accountJson != null) {
          _account = YTMusicAccount.fromJson(jsonDecode(accountJson));
        }

        if (kDebugMode) {print('✅ Auth cache restored (${_cookies.length} cookies)');}
        return true;
      }
    } catch (e) {
      if (kDebugMode) {print('Failed to restore auth cache: $e');}
    }
    return false;
  }

  /// Login with cookies from WebView
  Future<bool> loginWithCookies(
    Map<String, String> cookies, {
    YTMusicAccount? account,
  }) async {
    try {
      // Validate required cookies
      final hasAuth =
          cookies.containsKey('SAPISID') ||
          cookies.containsKey('__Secure-3PAPISID');
      if (!hasAuth) {
        if (kDebugMode) {print('Missing authentication cookies');}
        return false;
      }

      _cookies = cookies;
      _innerTubeService.setAuthCookies(cookies);

      // Verify authentication works
      await _innerTubeService.getLikedSongs();
      // Even empty results mean auth is working

      // Save cookies
      await _secureStorage.write(key: _cookiesKey, value: jsonEncode(cookies));

      // Save account info
      if (account != null) {
        _account = account;
        await _secureStorage.write(
          key: _accountInfoKey,
          value: jsonEncode(account.toJson()),
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {print('Login failed: $e');}
      return false;
    }
  }

  /// Logout and clear stored cookies
  Future<void> logout() async {
    _cookies.clear();
    _account = null;
    _innerTubeService.clearAuth();
    await _secureStorage.delete(key: _cookiesKey);
    await _secureStorage.delete(key: _accountInfoKey);
  }

  /// Get stored cookies for WebView initialization
  Map<String, String> getCookies() => Map.unmodifiable(_cookies);

  /// Parse cookies from WebView cookie string
  static Map<String, String> parseCookieString(String cookieString) {
    final cookies = <String, String>{};
    final pairs = cookieString.split('; ');

    for (final pair in pairs) {
      final index = pair.indexOf('=');
      if (index > 0) {
        final key = pair.substring(0, index);
        final value = pair.substring(index + 1);
        cookies[key] = value;
      }
    }

    return cookies;
  }

  /// Required cookies for authentication
  static const List<String> requiredCookies = [
    'SAPISID',
    '__Secure-3PAPISID',
    'HSID',
    'SSID',
    'SID',
    '__Secure-3PSID',
    'APISID',
    '__Secure-1PAPISID',
    '__Secure-1PSID',
  ];

  /// Check if cookies contain required auth cookies
  static bool hasRequiredCookies(Map<String, String> cookies) {
    return cookies.containsKey('SAPISID') ||
        cookies.containsKey('__Secure-3PAPISID');
  }
}

/// YouTube Music account information
class YTMusicAccount {
  final String? name;
  final String? email;
  final String? avatarUrl;
  final String? channelId;

  YTMusicAccount({this.name, this.email, this.avatarUrl, this.channelId});

  factory YTMusicAccount.fromJson(Map<String, dynamic> json) {
    return YTMusicAccount(
      name: json['name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      channelId: json['channelId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
    'channelId': channelId,
  };
}
