import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void _log(String msg) => debugPrint('[DiscordOAuth] $msg');

/// Result of a successful Discord OAuth2 authorization / refresh.
class DiscordTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresInSec;
  final String scope;

  const DiscordTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSec,
    required this.scope,
  });
}

class DiscordAuthException implements Exception {
  final String message;
  const DiscordAuthException(this.message);
  @override
  String toString() => 'DiscordAuthException: $message';
}

/// Discord OAuth2 (Authorization Code + PKCE), the same approach Metrolist
/// uses. Login happens in the system browser / Custom Tab — a real browser —
/// so passkeys, security keys and every 2FA method work (unlike an embedded
/// WebView). Discord redirects back to [redirectUri], which the app captures
/// via a manifest intent-filter + app_links.
class DiscordOAuth {
  static const String authorizeEndpoint =
      'https://discord.com/oauth2/authorize';
  static const String tokenEndpoint =
      'https://discord.com/api/v10/oauth2/token';

  /// Social SDK presence scope lets the OAuth access token drive Rich Presence
  /// over the Gateway; openid returns basic identity.
  static const String scopes = 'openid sdk.social_layer_presence';

  /// Must match the redirect URI registered in the Discord Developer Portal
  /// and the intent-filter in AndroidManifest.xml.
  static const String redirectUri = 'inzxdiscord://oauth2/callback';
  static const String _redirectScheme = 'inzxdiscord';

  /// Launches the browser authorization flow and returns the exchanged tokens.
  static Future<DiscordTokens> authorize(String clientId) async {
    final verifier = _randomUrlSafe(64);
    final challenge = _sha256Base64Url(verifier);
    final state = _randomUrlSafe(16);

    final appLinks = AppLinks();
    final completer = Completer<Uri>();
    StreamSubscription<Uri>? sub;
    sub = appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == _redirectScheme && !completer.isCompleted) {
        completer.complete(uri);
      }
    });

    try {
      _log('clientId=<$clientId> (len=${clientId.length})');
      _log('scope=<$scopes>');
      _log('redirect_uri=<$redirectUri>');

      final authUrl = Uri.parse(
        '$authorizeEndpoint'
        '?client_id=$clientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=${Uri.encodeComponent(scopes)}'
        '&state=$state'
        '&code_challenge_method=S256'
        '&code_challenge=$challenge',
      );
      _log('authorize URL: $authUrl');

      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.inAppBrowserView,
      );
      _log('browser launched=$launched');
      if (!launched) {
        throw const DiscordAuthException('Could not open a browser to sign in.');
      }

      final Uri callback;
      try {
        callback = await completer.future.timeout(const Duration(seconds: 180));
      } on TimeoutException {
        _log('TIMED OUT waiting for redirect callback');
        throw const DiscordAuthException('Sign-in timed out. Please try again.');
      }
      _log('callback received: $callback');

      final error = callback.queryParameters['error'];
      if (error != null) {
        final desc = callback.queryParameters['error_description'];
        _log('ERROR from Discord: $error — $desc');
        throw DiscordAuthException('Authorization denied: $error');
      }
      final returnedState = callback.queryParameters['state'];
      if (returnedState != state) {
        _log('state mismatch: sent=$state got=$returnedState');
        throw const DiscordAuthException('Security check failed (state mismatch).');
      }
      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const DiscordAuthException('No authorization code returned.');
      }
      _log('got authorization code (len=${code.length}), exchanging...');

      return await _exchange(
        clientId: clientId,
        grantType: 'authorization_code',
        extra: {
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
        },
      );
    } finally {
      await sub.cancel();
      // Best-effort: close the Custom Tab and return to the app.
      try {
        await closeInAppWebView();
      } catch (_) {}
    }
  }

  /// Exchanges a refresh token for a fresh access token.
  static Future<DiscordTokens> refresh(
    String clientId,
    String refreshToken,
  ) {
    return _exchange(
      clientId: clientId,
      grantType: 'refresh_token',
      extra: {'refresh_token': refreshToken},
    );
  }

  static Future<DiscordTokens> _exchange({
    required String clientId,
    required String grantType,
    required Map<String, String> extra,
  }) async {
    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(tokenEndpoint),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client_id': clientId,
              'grant_type': grantType,
              ...extra,
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw DiscordAuthException('Network error during sign-in: $e');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _log('token exchange ($grantType) HTTP ${resp.statusCode}: ${resp.body}');
      throw DiscordAuthException(
        'Token exchange failed (HTTP ${resp.statusCode}).',
      );
    }
    _log('token exchange ($grantType) OK (HTTP ${resp.statusCode})');

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return DiscordTokens(
      accessToken: json['access_token'] as String,
      refreshToken: (json['refresh_token'] as String?) ?? '',
      expiresInSec: (json['expires_in'] as num?)?.toInt() ?? 0,
      scope: (json['scope'] as String?) ?? scopes,
    );
  }

  static String _randomUrlSafe(int bytes) {
    final rnd = Random.secure();
    final data = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }

  static String _sha256Base64Url(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
