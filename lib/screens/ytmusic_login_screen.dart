import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/l10n/app_localizations_x.dart';
import '../providers/ytmusic_providers.dart';
import '../services/ytmusic_auth_service.dart';

class YTMusicLoginScreen extends ConsumerStatefulWidget {
  const YTMusicLoginScreen({super.key});

  @override
  ConsumerState<YTMusicLoginScreen> createState() => _YTMusicLoginScreenState();
}

class _YTMusicLoginScreenState extends ConsumerState<YTMusicLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isLoggingIn = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => _isLoading = false);
              _checkForLogin();
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _checkForLogin();
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              setState(() => _currentUrl = change.url!);
              _checkForLogin();
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F',
        ),
      );
  }

  Future<void> _checkForLogin() async {
    if (_isLoggingIn) return;

    // Check if we're on YouTube Music after login
    if (_currentUrl.startsWith('https://music.youtube.com') &&
        !_currentUrl.contains('accounts.google.com')) {
      // Small delay to ensure cookies are set
      await Future.delayed(const Duration(milliseconds: 500));
      await _extractCookiesAndLogin();
    }
  }

  Future<void> _extractCookiesAndLogin() async {
    if (_isLoggingIn) return;

    setState(() => _isLoggingIn = true);

    try {
      final cookieMap = <String, String>{};

      // Get cookies via JavaScript with a comprehensive approach
      // Note: HttpOnly cookies (like SAPISID) won't be accessible via JS
      // But we can try to get them using platform channel or accept limited functionality

      // First try to get visible cookies
      final cookieString = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );

      String cookieStr = cookieString.toString();
      if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
        cookieStr = cookieStr.substring(1, cookieStr.length - 1);
      }

      cookieMap.addAll(YTMusicAuthService.parseCookieString(cookieStr));

      // On Android, try to get cookies using platform channel
      if (Platform.isAndroid) {
        try {
          const platform = MethodChannel('inzx/cookies');
          final String? allCookies = await platform.invokeMethod('getCookies', {
            'url': 'https://music.youtube.com',
          });
          if (allCookies != null && allCookies.isNotEmpty) {
            cookieMap.addAll(YTMusicAuthService.parseCookieString(allCookies));
          }
        } on MissingPluginException {
          // Platform channel not available, continue with JS cookies
        } catch (e) {
          // Ignore
        }
      }

      // Check if we have minimum required cookies
      // For now, we'll accept login even without all cookies and try anyway
      final hasMinimalAuth =
          cookieMap.isNotEmpty &&
          (cookieMap.containsKey('SID') ||
              cookieMap.containsKey('HSID') ||
              cookieMap.containsKey('SSID'));

      if (YTMusicAuthService.hasRequiredCookies(cookieMap) || hasMinimalAuth) {
        // Try to get account info from YouTube Music page with retries
        YTMusicAccount? account;
        int retries = 0;

        while (retries < 3 && (account?.avatarUrl == null)) {
          if (retries > 0) {
            if (kDebugMode) {
              print('Retrying avatar extraction (attempt ${retries + 1})...');
            }
            await Future.delayed(const Duration(seconds: 2));
          }

          try {
            final accountInfo = await _controller.runJavaScriptReturningResult(
              '''
                (function() {
                  try {
                    // Try multiple sources for account info
                    var ytInitialData = window.ytInitialData || {};
                    var ytcfg = window.ytcfg || {};
                    
                    var name = null;
                    var email = null;
                    var avatarUrl = null;
                    
                    // Method 1: From ytcfg
                    if (ytcfg.data_ && ytcfg.data_.DELEGATED_SESSION_ID) {
                      var user = ytcfg.data_;
                      avatarUrl = user.LOGGED_IN_USER_PROFILE_URL || null;
                    }
                    
                    // Method 2: From header
                    if (ytInitialData.header) {
                      var header = ytInitialData.header;
                      if (header.musicVisualHeaderRenderer) {
                        name = header.musicVisualHeaderRenderer.title?.runs?.[0]?.text || null;
                      }
                    }
                    
                    // Method 3: From account button in the page
                    // Try generic "Account" label or associated aria labels
                    var accountBtn = document.querySelector('button[aria-label*="Account"]') || 
                                     document.querySelector('button[aria-label*="account"]') ||
                                     document.querySelector('button[aria-label*="Profile"]') ||
                                     document.querySelector('yt-music-settings-button');
                                     
                    if (accountBtn) {
                      var img = accountBtn.querySelector('img');
                      if (img && img.src) {
                        avatarUrl = img.src.replace('=s32-', '=s120-').replace('=s88-', '=s120-');
                      }
                    }
                    
                    // Method 4: Scan for profile image based on heuristics (Position & Size)
                    // Must be in the header (top < 100px) and small (avatar size)
                    if (!avatarUrl) {
                      var imgs = document.querySelectorAll('img');
                      var bestCandidate = null;
                      
                      for (var i = 0; i < imgs.length; i++) {
                         var img = imgs[i];
                         var src = img.src;
                         var rect = img.getBoundingClientRect();
                         
                         // Check valid src
                         if (!src || !src.includes('googleusercontent.com') || src.includes('yt_music_logo')) continue;
                         
                         // Check position: Must be at the top of the page (header area)
                         // And likely on the right side
                         if (rect.top > 100) continue; 
                         
                         // Check size: Must be small-ish (icon size)
                         // Profile pics are usually square-ish
                         var isSquare = Math.abs(rect.width - rect.height) < 10;
                         var isIconSize = rect.width > 20 && rect.width < 80;
                         
                         if (isSquare && isIconSize) {
                           // This is very likely the profile picture
                           avatarUrl = src;
                           break;
                         }
                      }
                    }
                    
                    return JSON.stringify({
                      name: name,
                      email: email,
                      avatarUrl: avatarUrl,
                      debug: {
                        attempt: $retries + 1,
                        method1: !!(ytcfg.data_ && ytcfg.data_.DELEGATED_SESSION_ID),
                        method2: !!(ytInitialData.header && ytInitialData.header.musicVisualHeaderRenderer),
                        foundUrl: avatarUrl
                      }
                    });
                  } catch(e) {
                    return JSON.stringify({ error: e.toString() });
                  }
                })();
              ''',
            );

            if (kDebugMode) {
              print(
                'Raw Account Info Extraction Result (Attempt ${retries + 1}): $accountInfo',
              );
            }

            // Handle double-encoding if present
            dynamic decoded = accountInfo;
            if (decoded is String && decoded.startsWith('"')) {
              try {
                decoded = jsonDecode(decoded);
              } catch (_) {}
            }

            if (decoded is String &&
                decoded != '{}' &&
                !decoded.contains('"error":')) {
              final data = jsonDecode(decoded);
              final extractedAccount = YTMusicAccount.fromJson(data);

              // Merge info if we found better data
              if (extractedAccount.avatarUrl != null) {
                account = extractedAccount;
              } else {
                account ??= extractedAccount;
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing account info attempt $retries: $e');
            }
          }

          retries++;
        }

        // Login with cookies
        final authNotifier = ref.read(ytMusicAuthStateProvider.notifier);
        final success = await authNotifier.login(cookieMap, account: account);

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.loggedInYoutubeMusicSuccess),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
          return;
        }
      }

      // If we reach here, login wasn't successful yet
      setState(() => _isLoggingIn = false);
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting cookies: $e');
      }
      setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : colorScheme.surface,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.white : colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          context.l10n.signInToYoutubeMusic,
          style: TextStyle(
            color: isDark ? Colors.white : colorScheme.onSurface,
          ),
        ),
        actions: [
          if (_isLoading || _isLoggingIn)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoggingIn)
            Container(
              color: isDark ? Colors.black87 : Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.loggingYouIn,
                      style: TextStyle(
                        color: isDark ? Colors.white : colorScheme.onSurface,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        child: Text(
          context.l10n.signInSyncYoutubeMusicDescription,
          style: TextStyle(
            color: isDark
                ? Colors.grey
                : colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
