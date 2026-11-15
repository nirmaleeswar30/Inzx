import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/l10n/app_localizations_x.dart';
import '../providers/ytmusic_providers.dart';
import '../services/ytmusic_auth_service.dart';
import 'ytmusic_login_screen.dart';

/// YouTube Music sign-in on Windows and Linux. webview_flutter has no desktop
/// backend, so Google's page opens in its own window and this screen waits for
/// it; the native cookie store also gives us the HttpOnly session cookies.
class DesktopYTMusicLoginState extends ConsumerState<YTMusicLoginScreen> {
  static const _signInUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube&uilel=3'
      '&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  // The account avatar shown in settings, read from the signed-in page.
  static const _accountScript = '''
    (function() {
      var button = document.querySelector('button[aria-label*="ccount"]');
      var img = button ? button.querySelector('img') : null;
      return JSON.stringify({
        avatarUrl: img && img.src ? img.src.replace('=s32-', '=s120-') : null
      });
    })();
  ''';

  Webview? _webview;
  Timer? _poll;
  bool _checking = false;
  bool _done = false;
  String? _error;

  /// Sign-ins that reached YouTube (its cookies were there) but didn't
  /// complete. A few in a row stop the polling with an error: before, a
  /// failure (an unsaved sign-in, YouTube refusing the cookies) was retried
  /// every 2 seconds forever behind the spinner.
  int _failedLogins = 0;
  static const _maxFailedLogins = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (!_done) _webview?.close();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      if (!await WebviewWindow.isWebviewAvailable()) {
        _fail(
          'A web runtime is needed to sign in. Install Microsoft Edge WebView2 '
          'on Windows, or WebKitGTK on Linux, then try again.',
        );
        return;
      }
      final support = await getApplicationSupportDirectory();
      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: 520,
          windowHeight: 760,
          title: 'Sign in to YouTube Music',
          windows: WindowsWebviewOptions(
            userDataFolder: p.join(support.path, 'webview_login'),
          ),
        ),
      );
      _webview = webview;
      unawaited(webview.onClose.whenComplete(_onWindowClosed));
      await webview.launch(_signInUrl);
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (e) {
      debugPrint('Desktop sign-in failed to open: $e');
      _fail('The sign-in window could not be opened.');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  /// After a failed sign-in: check the still-open window again.
  void _retry() {
    final webview = _webview;
    if (webview == null) return;
    setState(() {
      _error = null;
      _failedLogins = 0;
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    unawaited(_check());
  }

  void _onWindowClosed() {
    _poll?.cancel();
    if (!_done && mounted && _error == null) Navigator.of(context).pop(false);
  }

  Future<void> _check() async {
    final webview = _webview;
    if (_checking || _done || webview == null) return;
    _checking = true;
    try {
      final href = await webview.evaluateJavaScript('location.href');
      if (href is! String || !href.startsWith('https://music.youtube.com')) {
        return;
      }

      // Google's own cookies share these names: only YouTube's will do.
      final cookies = <String, String>{
        for (final cookie in await webview.getAllCookies())
          if (cookie.domain.endsWith('youtube.com')) cookie.name: cookie.value,
      };
      if (!YTMusicAuthService.hasRequiredCookies(cookies)) return;

      final success = await ref
          .read(ytMusicAuthStateProvider.notifier)
          .login(cookies, account: await _readAccount(webview));
      if (!mounted) return;
      if (!success) {
        if (++_failedLogins >= _maxFailedLogins) {
          _poll?.cancel();
          _fail(
            'You signed in, but Inzx couldn\'t finish connecting your '
            'account. Check your internet connection and try again.',
          );
        }
        return;
      }

      _done = true;
      _poll?.cancel();
      await webview.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.loggedInYoutubeMusicSuccess),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Desktop sign-in check failed: $e');
    } finally {
      _checking = false;
    }
  }

  Future<YTMusicAccount?> _readAccount(Webview webview) async {
    try {
      final raw = await webview.evaluateJavaScript(_accountScript);
      final data = raw is String ? jsonDecode(raw) : raw;
      return data is Map<String, dynamic>
          ? YTMusicAccount.fromJson(data)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to YouTube Music')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                error ?? 'Finish signing in in the window that just opened.',
                textAlign: TextAlign.center,
              ),
              if (error != null && _webview != null && _failedLogins > 0) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: _retry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
