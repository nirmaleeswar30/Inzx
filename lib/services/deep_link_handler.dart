import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/widgets/playlist_screen.dart';
import '../screens/widgets/artist_screen.dart';
import '../screens/widgets/album_screen.dart';
import 'audio_handler.dart';
import '../main.dart';

class DeepLinkHandler {
  static final DeepLinkHandler instance = DeepLinkHandler._();
  DeepLinkHandler._();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  bool _isInitialized = false;

  void initialize(BuildContext context, WidgetRef ref) {
    if (_isInitialized) return;
    _isInitialized = true;
    _appLinks = AppLinks();

    // Handle incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri, context, ref);
      }
    }, onError: (err) {
      debugPrint('Error handling deep link: $err');
    });

    // Handle initial link if app was launched from a link
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        // Wait a frame for navigation stack to be ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleDeepLink(uri, context, ref);
        });
      }
    });
  }

  void _handleDeepLink(Uri uri, BuildContext context, WidgetRef ref) {
    debugPrint('Received Deep Link: $uri');

    // Expected format: inzx://open/<type>?id=<id>
    if (uri.scheme == 'inzx' && uri.host == 'open') {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isEmpty) return;

      final type = pathSegments.first; // e.g., 'playlist', 'album', 'artist', 'song'
      final id = uri.queryParameters['id'];

      if (id == null || id.isEmpty) return;

      switch (type) {
        case 'playlist':
          PlaylistScreen.open(context, playlistId: id);
          break;
        case 'album':
          AlbumScreen.open(context, albumId: id);
          break;
        case 'artist':
          ArtistScreen.open(context, artistId: id);
          break;
        case 'song':
          // For a song, we can just play it using the audio handler
          if (audioHandler != null) {
            audioHandler!.playFromMediaId(id);
          }
          break;
        default:
          debugPrint('Unknown deep link type: $type');
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  /// Creates a base64 encoded redirect URL for sharing.
  /// [type] should be 'playlist', 'album', 'artist', or 'song'.
  static String createShareUrl(String type, String id) {
    final deepLink = 'inzx://open/$type?id=$id';
    final bytes = utf8.encode(deepLink);
    final base64DeepLink = base64.encode(bytes);
    
    // Fallback to github pages redirect url
    final baseUrl = 'https://nirmaleeswar30.github.io/Inzx/redirect.html';
    return '$baseUrl?url=$base64DeepLink';
  }
}
