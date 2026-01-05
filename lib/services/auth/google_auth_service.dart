import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// User profile from Google Sign-In
class GoogleUserProfile {
  final String id;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  const GoogleUserProfile({
    required this.id,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'photoUrl': photoUrl,
  };

  factory GoogleUserProfile.fromJson(Map<String, dynamic> json) {
    return GoogleUserProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  /// Get initials for avatar fallback
  String get initials {
    if (displayName == null || displayName!.isEmpty) {
      return email?.substring(0, 1).toUpperCase() ?? 'U';
    }
    final parts = displayName!.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName![0].toUpperCase();
  }
}

/// Google Sign-In service - standalone, no Firebase required
class GoogleAuthService {
  static const _cacheKey = 'google_user_profile';

  // Web Client ID from Google Cloud Console (required for Android)
  static const _webClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: _webClientId,
  );

  GoogleUserProfile? _currentUser;
  GoogleUserProfile? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Initialize and check for existing sign-in
  Future<bool> initialize() async {
    try {
      // Try to restore from cache first
      final cached = await _loadFromCache();
      if (cached != null) {
        _currentUser = cached;
        if (kDebugMode) {
          print('GoogleAuth: Restored user from cache: ${cached.displayName}');
        }

        // Verify still signed in with Google silently
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          // Update profile in case it changed
          _currentUser = GoogleUserProfile(
            id: account.id,
            displayName: account.displayName,
            email: account.email,
            photoUrl: account.photoUrl,
          );
          await _saveToCache(_currentUser!);
          return true;
        } else {
          // Silent sign-in failed, but we have cached data
          // Keep using cache for now
          return true;
        }
      }

      // No cache, try silent sign-in
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentUser = GoogleUserProfile(
          id: account.id,
          displayName: account.displayName,
          email: account.email,
          photoUrl: account.photoUrl,
        );
        await _saveToCache(_currentUser!);
        if (kDebugMode) {
          print(
            'GoogleAuth: Silent sign-in successful: ${account.displayName}',
          );
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Initialize error: $e');
      }
    }
    return false;
  }

  /// Sign in with Google (shows account picker)
  Future<GoogleUserProfile?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        _currentUser = GoogleUserProfile(
          id: account.id,
          displayName: account.displayName,
          email: account.email,
          photoUrl: account.photoUrl,
        );
        await _saveToCache(_currentUser!);
        if (kDebugMode) {
          print('GoogleAuth: Sign-in successful: ${account.displayName}');
        }
        return _currentUser;
      }
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Sign-in error: $e');
      }
    }
    return null;
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      await _clearCache();
      if (kDebugMode) {
        print('GoogleAuth: Signed out');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Sign-out error: $e');
      }
    }
  }

  /// Disconnect (revoke access)
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
      await _clearCache();
      if (kDebugMode) {
        print('GoogleAuth: Disconnected');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Disconnect error: $e');
      }
    }
  }

  // ============ Cache Management ============

  Future<void> _saveToCache(GoogleUserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(profile.toJson()));
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Cache save error: $e');
      }
    }
  }

  Future<GoogleUserProfile?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json != null) {
        return GoogleUserProfile.fromJson(jsonDecode(json));
      }
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Cache load error: $e');
      }
    }
    return null;
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      if (kDebugMode) {
        print('GoogleAuth: Cache clear error: $e');
      }
    }
  }
}
