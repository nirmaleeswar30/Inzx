import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/track.dart';
import '../providers/music_providers.dart';
import '../providers/ytmusic_providers.dart';
import '../screens/widgets/playlist_screen.dart';
import '../screens/widgets/podcast_screen.dart';
import '../screens/widgets/artist_screen.dart';
import '../screens/widgets/album_screen.dart';
import '../screens/widgets/now_playing_screen.dart';
import '../screens/jams_screen.dart';
import '../screens/ytmusic_login_screen.dart';
import '../providers/jams_provider.dart';

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
        _handleDeepLink(uri, ref);
      }
    }, onError: (err) {
      debugPrint('Error handling deep link: $err');
    });

    // Handle initial link if app was launched from a link
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        // Wait for rootNavigatorKey context to be mounted & ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleDeepLink(uri, ref);
        });
      }
    });
  }

  void _handleDeepLink(Uri uri, WidgetRef ref) {
    debugPrint('DeepLinkHandler: Received link -> $uri');

    // 1. Custom scheme: inzx://open/<type>?id=<id>
    if (uri.scheme == 'inzx' && uri.host == 'open') {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isEmpty) return;

      final type = pathSegments.first; // 'playlist', 'album', 'artist', 'song'
      final id = uri.queryParameters['id'];

      if (id == null || id.isEmpty) return;

      _navigateToItem(type, id, ref);
      return;
    }

    // 2. Short links: https://inzx.nirmaleeswar.dev/<s|a|p|ar|pod|jam>/<id>
    if (uri.host == shareHost && uri.pathSegments.length >= 2) {
      final type = _shortPathTypes[uri.pathSegments[0]];
      final id = uri.pathSegments[1];
      if (type != null && id.isNotEmpty) {
        _navigateToItem(type, id, ref);
        return;
      }
    }

    // 3. Legacy long links: .../redirect.html?url=<base64 deep link>
    if ((uri.host.contains('github.io') || uri.host == shareHost) &&
        uri.queryParameters.containsKey('url')) {
      final rawUrlParam = uri.queryParameters['url']!;
      final decodedString = _decodeBase64Url(rawUrlParam);
      if (decodedString != null) {
        try {
          final decodedUri = Uri.parse(decodedString);
          _handleDeepLink(decodedUri, ref);
          return;
        } catch (e) {
          debugPrint('Error parsing decoded deep link URI: $e');
        }
      }
    }
  }

  void _navigateToItem(String type, String id, WidgetRef ref) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLinkHandler: rootNavigatorKey.currentContext is null');
      return;
    }

    switch (type) {
      case 'podcast':
        PodcastScreen.open(context, podcastId: id);
        break;
      case 'playlist':
        if (id.startsWith('MPSP')) {
          PodcastScreen.open(context, podcastId: id);
        } else {
          PlaylistScreen.open(context, playlistId: id);
        }
        break;
      case 'album':
        AlbumScreen.open(context, albumId: id);
        break;
      case 'artist':
        ArtistScreen.open(context, artistId: id);
        break;
      case 'song':
      case 'track':
      case 'video':
        _handleSongDeepLink(id, ref);
        break;
      case 'jam':
        _handleJamDeepLink(id, ref);
        break;
      default:
        debugPrint('Unknown deep link type: $type');
    }
  }

  Future<void> _handleJamDeepLink(String code, WidgetRef ref) async {
    final upperCode = code.toUpperCase();
    final messenger = rootScaffoldMessengerKey.currentState;
    if (ref.read(appAccountProvider) == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Sign in to join this Jam')),
      );
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final signedIn = await openSignIn(context);
      if (!signedIn) return;
      // Give the Jams service a moment to come up for the new account.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Joining Jam $upperCode...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final joined = await ref
        .read(jamsNotifierProvider.notifier)
        .joinSession(upperCode);
    final navContext = rootNavigatorKey.currentContext;
    if (joined && navContext != null && navContext.mounted) {
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const JamsScreen()),
      );
    } else if (!joined) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not join that Jam')),
      );
    }
  }

  Future<void> _handleSongDeepLink(String songId, WidgetRef ref) async {
    try {
      debugPrint('DeepLinkHandler: Loading target song $songId...');

      final messenger = rootScaffoldMessengerKey.currentState;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Opening shared song...'),
          duration: Duration(seconds: 2),
        ),
      );

      final ytService = ref.read(innerTubeServiceProvider);
      Track? targetTrack = await ytService.getSongDetails(songId);

      targetTrack ??= Track(
        id: songId,
        title: 'Shared Song',
        artist: 'YouTube Music',
        thumbnailUrl: 'https://img.youtube.com/vi/$songId/hqdefault.jpg',
        duration: Duration.zero,
      );

      final playerService = ref.read(audioPlayerServiceProvider);
      await playerService.playTrack(targetTrack, enableRadio: true);

      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        NowPlayingScreen.show(context);
      }
    } catch (e, stack) {
      debugPrint('Error loading deep linked song $songId: $e\n$stack');
    }
  }

  static String? _decodeBase64Url(String raw) {
    try {
      String normalized = Uri.decodeComponent(raw).replaceAll(' ', '+');
      switch (normalized.length % 4) {
        case 2:
          normalized += '==';
          break;
        case 3:
          normalized += '=';
          break;
      }
      final bytes = base64.decode(normalized);
      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('Base64 decode error: $e');
      return null;
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  /// When true, [createShareUrl] returns the native YouTube Music link instead
  /// of an Inzx deep link. Kept in sync with the user's setting by
  /// [ShareNativeLinksNotifier].
  static bool useNativeYtMusicLinks = false;

  static const String shareNativeLinksPrefKey =
      'inzx_share_native_ytmusic_links';

  /// Build a plain YouTube Music URL for a shared item, or null for a type
  /// that has no direct equivalent.
  static String? nativeYtMusicUrl(String type, String id) {
    switch (type) {
      case 'song':
        return 'https://music.youtube.com/watch?v=$id';
      case 'podcast':
        final pl = id.startsWith('MPSP') ? id.substring(4) : id;
        return 'https://music.youtube.com/playlist?list=$pl';
      case 'playlist':
        final list = id.startsWith('VL') ? id.substring(2) : id;
        return 'https://music.youtube.com/playlist?list=$list';
      case 'album':
        return 'https://music.youtube.com/browse/$id';
      case 'artist':
        return 'https://music.youtube.com/channel/$id';
    }
    return null;
  }

  /// Domain that hosts the landing page, share previews and the redirect.
  static const String shareHost = 'inzx.nirmaleeswar.dev';

  static const Map<String, String> _shortPathTypes = {
    's': 'song',
    'a': 'album',
    'p': 'playlist',
    'ar': 'artist',
    'pod': 'podcast',
    'jam': 'jam',
  };

  static const Map<String, String> _shortPathForType = {
    'song': 's',
    'track': 's',
    'video': 's',
    'album': 'a',
    'playlist': 'p',
    'artist': 'ar',
    'podcast': 'pod',
    'jam': 'jam',
  };

  /// Creates a share URL for the given item.
  /// [type] should be 'playlist', 'album', 'artist', 'podcast' or 'song'.
  ///
  /// Returns a native YouTube Music link when the user has opted out of Inzx
  /// deep links; otherwise a short link (`https://inzx.nirmaleeswar.dev/s/<id>`)
  /// whose preview card shows the artwork and which opens the item in Inzx.
  static String createShareUrl(String type, String id) {
    if (useNativeYtMusicLinks) {
      final native = nativeYtMusicUrl(type, id);
      if (native != null) return native;
    }
    final path = _shortPathForType[type] ?? type;
    return 'https://$shareHost/$path/${Uri.encodeComponent(id)}';
  }

  /// Invite link for a Jam. [videoId] (what's playing) lets the preview card
  /// show that song's artwork.
  static String createJamInviteUrl(String code, {String? videoId}) {
    final base = 'https://$shareHost/jam/${code.toUpperCase()}';
    if (videoId == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      return base;
    }
    return '$base?v=$videoId';
  }
}

/// Opens the share sheet with a Jam invite link (its preview shows what's
/// playing, and opening it joins the Jam in Inzx).
Future<void> shareJamInvite(String code, {String? videoId}) async {
  final link = DeepLinkHandler.createJamInviteUrl(code, videoId: videoId);
  await SharePlus.instance.share(
    ShareParams(
      text: 'Join my Jam on Inzx and listen along with me 🎧\n$link',
      subject: 'Join my Jam',
    ),
  );
}
