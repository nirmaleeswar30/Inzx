import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// InnerTube API client for YouTube Music
/// This replicates the internal API that YouTube Music web/app uses
class InnerTubeService {
  static const String _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static const String _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  // Client context for requests
  static const Map<String, dynamic> _clientContext = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20231204.01.00',
      'hl': 'en',
      'gl': 'US',
      'experimentIds': [],
      'experimentsToken': '',
      'browserName': 'Chrome',
      'browserVersion': '120.0.0.0',
      'osName': 'Windows',
      'osVersion': '10.0',
      'platform': 'DESKTOP',
      'utcOffsetMinutes': 0,
    },
    'user': {'lockedSafetyMode': false},
  };

  String? _sapisid;
  String? _psid;
  Map<String, String> _cookies = {};

  /// Whether the user is authenticated
  bool get isAuthenticated => _sapisid != null && _sapisid!.isNotEmpty;

  /// Set authentication cookies from WebView login
  void setAuthCookies(Map<String, String> cookies) {
    _cookies = cookies;
    _sapisid = cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];
    _psid = cookies['__Secure-3PSID'] ?? cookies['SID'];
  }

  /// Clear authentication
  void clearAuth() {
    _cookies.clear();
    _sapisid = null;
    _psid = null;
  }

  /// Generate SAPISIDHASH for authenticated requests
  String? _generateSapisidHash() {
    if (_sapisid == null) return null;

    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final data = '$timestamp $_sapisid https://music.youtube.com';
    final hash = sha1.convert(utf8.encode(data)).toString();
    return 'SAPISIDHASH ${timestamp}_$hash';
  }

  /// Build headers for API requests
  Map<String, String> _buildHeaders({bool authenticated = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
      'X-Goog-Visitor-Id': _generateVisitorId(),
    };

    if (authenticated && isAuthenticated) {
      final sapisidHash = _generateSapisidHash();
      if (sapisidHash != null) {
        headers['Authorization'] = sapisidHash;
      }
      headers['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      headers['X-Goog-AuthUser'] = '0';
    }

    return headers;
  }

  String _generateVisitorId() {
    final random = Random();
    final chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(11, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Make an InnerTube API request
  /// JSON decoding runs in background isolate for large responses
  Future<Map<String, dynamic>?> _request(
    String endpoint,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/$endpoint?key=$_apiKey&prettyPrint=false',
      );

      final requestBody = {'context': _clientContext, ...body};

      final response = await http.post(
        url,
        headers: _buildHeaders(authenticated: authenticated),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // Decode JSON in background isolate to avoid UI jank
        // Large responses (home page, search) can cause stuttering
        return await compute(_jsonDecodeIsolate, response.body);
      } else {
        if (kDebugMode) {
          print('InnerTube error ${response.statusCode}: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTube request failed: $e');
      }
      return null;
    }
  }

  // ============ LIBRARY ENDPOINTS ============

  /// Get user's liked songs (fetches all pages using playlist endpoint)
  Future<List<Track>> getLikedSongs() async {
    if (!isAuthenticated) return [];

    // Use the special "LM" playlist ID for liked songs - this is more reliable
    // than the FEmusic_liked_videos browse endpoint
    final allTracks = <Track>[];
    String? continuation;

    // First request - get playlist with VL prefix
    final response = await _request('browse', {
      'browseId': 'VLLM', // VL + LM (Liked Music)
    }, authenticated: true);

    if (response == null) {
      if (kDebugMode) {
        print('LikedSongs: Initial response is null, trying fallback...');
      }
      return _getLikedSongsFallback();
    }

    // Parse first page and get continuation
    final (tracks, cont) = _parseLikedSongsPlaylist(response);
    allTracks.addAll(tracks);
    continuation = cont;
    if (kDebugMode) {
      print(
        'LikedSongs: First page: ${tracks.length} songs, continuation: ${cont != null}',
      );
    }

    // Fetch remaining pages
    int pageNum = 1;
    while (continuation != null) {
      pageNum++;
      final contResponse = await _request('browse', {
        'continuation': continuation,
      }, authenticated: true);

      if (contResponse == null) {
        if (kDebugMode) {
          print('LikedSongs: Page $pageNum: null response');
        }
        break;
      }

      final (moreTracks, nextCont) = _parseLikedSongsContinuation(contResponse);
      allTracks.addAll(moreTracks);
      if (kDebugMode) {
        print(
          'LikedSongs: Page $pageNum: ${moreTracks.length} songs, continuation: ${nextCont != null}',
        );
      }
      continuation = nextCont;

      // Safety limit to prevent infinite loops
      if (allTracks.length > 5000) break;
    }

    if (kDebugMode) {
      print('LikedSongs: Total fetched: ${allTracks.length} songs');
    }
    return allTracks;
  }

  /// Fallback method using FEmusic_liked_videos (old method)
  Future<List<Track>> _getLikedSongsFallback() async {
    final response = await _request('browse', {
      'browseId': 'FEmusic_liked_videos',
    }, authenticated: true);

    if (response == null) return [];

    final (tracks, _) = _parseLibraryTracksWithContinuation(response);
    if (kDebugMode) {
      print('LikedSongs Fallback: Got ${tracks.length} songs');
    }
    return tracks;
  }

  /// Parse liked songs from VLLM playlist response
  (List<Track>, String?) _parseLikedSongsPlaylist(
    Map<String, dynamic> response,
  ) {
    final tracks = <Track>[];
    String? continuation;

    try {
      // Debug: Print response structure
      if (kDebugMode) {
        print('LikedSongs: Response keys: ${response.keys.toList()}');
      }
      if (response['contents'] != null) {
        final contents = response['contents'] as Map;
        if (kDebugMode) {
          print('LikedSongs: contents keys: ${contents.keys.toList()}');
        }

        // For two column layout
        if (contents['twoColumnBrowseResultsRenderer'] != null) {
          final tcbr = contents['twoColumnBrowseResultsRenderer'] as Map;
          if (kDebugMode) {
            print(
              'LikedSongs: twoColumnBrowseResultsRenderer keys: ${tcbr.keys.toList()}',
            );
          }

          if (tcbr['secondaryContents'] != null) {
            final sc = tcbr['secondaryContents'] as Map;
            if (kDebugMode) {
              print('LikedSongs: secondaryContents keys: ${sc.keys.toList()}');
            }

            final sectionList = sc['sectionListRenderer'] as Map?;
            if (sectionList != null) {
              final sections = sectionList['contents'] as List?;
              if (sections != null && sections.isNotEmpty) {
                if (kDebugMode) {
                  print(
                    'LikedSongs: First section keys: ${(sections[0] as Map).keys.toList()}',
                  );
                }
              }
            }
          }
        }
      }

      // Try twoColumnBrowseResultsRenderer > secondaryContents first (VLLM playlist)
      var contents =
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
                'contents',
              ])
              as List?;

      var shelf =
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
              ])
              as Map?;

      // Check for continuation at sectionListRenderer level (twoColumn)
      var sectionListRenderer =
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
              ])
              as Map?;

      if (sectionListRenderer != null) {
        if (kDebugMode) {
          print(
            'LikedSongs: sectionListRenderer keys: ${sectionListRenderer.keys.toList()}',
          );
        }
        final continuations = sectionListRenderer['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          if (kDebugMode) {
            print(
              'LikedSongs: Found continuation at sectionListRenderer level',
            );
          }
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        }
      }

      // Also try musicShelfRenderer in twoColumn layout
      if (contents == null) {
        contents =
            _navigateJson(response, [
                  'contents',
                  'twoColumnBrowseResultsRenderer',
                  'secondaryContents',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicShelfRenderer',
                  'contents',
                ])
                as List?;

        shelf =
            _navigateJson(response, [
                  'contents',
                  'twoColumnBrowseResultsRenderer',
                  'secondaryContents',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicShelfRenderer',
                ])
                as Map?;
      }

      // Fallback: try singleColumnBrowseResultsRenderer
      if (contents == null) {
        contents =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicPlaylistShelfRenderer',
                  'contents',
                ])
                as List?;

        shelf =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicPlaylistShelfRenderer',
                ])
                as Map?;
      }

      // Try musicShelfRenderer in singleColumn
      if (contents == null) {
        contents =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicShelfRenderer',
                  'contents',
                ])
                as List?;

        shelf =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicShelfRenderer',
                ])
                as Map?;
      }

      // Get continuation from shelf
      if (shelf != null) {
        if (kDebugMode) {
          print('LikedSongs: shelf keys: ${shelf.keys.toList()}');
        }
        final continuations = shelf['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          if (kDebugMode) {
            print(
              'LikedSongs: continuations[0] keys: ${(continuations[0] as Map).keys.toList()}',
            );
          }
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        } else {
          if (kDebugMode) {
            print('LikedSongs: No continuations array in shelf');
          }
        }
      }

      if (contents != null) {
        for (final item in contents) {
          final track = _parseTrackItem(item);
          if (track != null) tracks.add(track);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing liked songs playlist: $e');
      }
    }

    return (tracks, continuation);
  }

  /// Parse liked songs continuation response
  (List<Track>, String?) _parseLikedSongsContinuation(
    Map<String, dynamic> response,
  ) {
    final tracks = <Track>[];
    String? continuation;

    try {
      // Try musicPlaylistShelfContinuation
      var continuationContents =
          response['continuationContents']?['musicPlaylistShelfContinuation'];

      // Fall back to musicShelfContinuation
      continuationContents ??=
          response['continuationContents']?['musicShelfContinuation'];

      if (continuationContents != null) {
        final items = continuationContents['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final track = _parseTrackItem(item);
            if (track != null) tracks.add(track);
          }
        }

        // Get next continuation token
        final continuations = continuationContents['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing liked songs continuation: $e');
      }
    }

    return (tracks, continuation);
  }

  /// Get user's library songs (uploaded/private)
  Future<List<Track>> getLibrarySongs() async {
    if (!isAuthenticated) return [];

    final response = await _request('browse', {
      'browseId': 'FEmusic_library_privately_owned_tracks',
    }, authenticated: true);

    if (response == null) return [];
    return _parseLibraryTracks(response);
  }

  /// Get user's saved albums
  Future<List<Album>> getSavedAlbums() async {
    if (!isAuthenticated) return [];

    final response = await _request('browse', {
      'browseId': 'FEmusic_liked_albums',
    }, authenticated: true);

    if (response == null) return [];
    return _parseLibraryAlbums(response);
  }

  /// Get user's saved playlists
  Future<List<Playlist>> getSavedPlaylists() async {
    if (!isAuthenticated) return [];

    final response = await _request('browse', {
      'browseId': 'FEmusic_liked_playlists',
    }, authenticated: true);

    if (response == null) return [];
    return _parseLibraryPlaylists(response);
  }

  /// Get user's subscribed artists
  Future<List<Artist>> getSubscribedArtists() async {
    if (!isAuthenticated) return [];

    final response = await _request('browse', {
      'browseId': 'FEmusic_library_corpus_track_artists',
    }, authenticated: true);

    if (response == null) return [];
    return _parseLibraryArtists(response);
  }

  /// Get recently played
  Future<List<Track>> getRecentlyPlayed() async {
    if (!isAuthenticated) return [];

    final response = await _request('browse', {
      'browseId': 'FEmusic_history',
    }, authenticated: true);

    if (response == null) return [];
    return _parseHistoryTracks(response);
  }

  /// Get home page content (personalized recommendations)
  Future<HomePageContent> getHomePageContent() async {
    final response = await _request('browse', {
      'browseId': 'FEmusic_home',
    }, authenticated: isAuthenticated);

    if (response == null) return HomePageContent.empty;
    return _parseHomePageContent(response);
  }

  /// Load more home page content using continuation token
  Future<HomePageContent> getHomePageContinuation(
    String continuationToken,
  ) async {
    final response = await _request('browse', {
      'continuation': continuationToken,
    }, authenticated: isAuthenticated);

    if (response == null) return HomePageContent.empty;
    return _parseHomePageContinuation(response);
  }

  /// Get raw home page response (for debugging)
  Future<Map<String, dynamic>?> getHomePage() async {
    final response = await _request('browse', {
      'browseId': 'FEmusic_home',
    }, authenticated: isAuthenticated);

    return response;
  }

  // ============ ACTIONS ============

  /// Like or unlike a song
  Future<bool> likeVideo(String videoId, bool like) async {
    if (!isAuthenticated) return false;

    final response = await _request(like ? 'like/like' : 'like/removelike', {
      'target': {'videoId': videoId},
    }, authenticated: true);

    return response != null;
  }

  /// Subscribe or unsubscribe from an artist
  Future<bool> subscribeArtist(String channelId, bool subscribe) async {
    if (!isAuthenticated) return false;

    final endpoint = subscribe
        ? 'subscription/subscribe'
        : 'subscription/unsubscribe';
    final response = await _request(endpoint, {
      'channelIds': [channelId],
    }, authenticated: true);

    return response != null;
  }

  /// Add song to playlist
  Future<bool> addToPlaylist(String playlistId, String videoId) async {
    if (!isAuthenticated) return false;

    final response = await _request('browse/edit_playlist', {
      'playlistId': playlistId,
      'actions': [
        {'action': 'ACTION_ADD_VIDEO', 'addedVideoId': videoId},
      ],
    }, authenticated: true);

    return response != null;
  }

  /// Remove song from playlist
  Future<bool> removeFromPlaylist(
    String playlistId,
    String videoId,
    String setVideoId,
  ) async {
    if (!isAuthenticated) return false;

    final response = await _request('browse/edit_playlist', {
      'playlistId': playlistId,
      'actions': [
        {
          'action': 'ACTION_REMOVE_VIDEO',
          'removedVideoId': videoId,
          'setVideoId': setVideoId,
        },
      ],
    }, authenticated: true);

    return response != null;
  }

  /// Create a new playlist
  Future<String?> createPlaylist(
    String title, {
    String? description,
    bool isPrivate = true,
  }) async {
    if (!isAuthenticated) return null;

    final response = await _request('playlist/create', {
      'title': title,
      'description': description ?? '',
      'privacyStatus': isPrivate ? 'PRIVATE' : 'PUBLIC',
    }, authenticated: true);

    if (response == null) return null;
    return response['playlistId'] as String?;
  }

  /// Delete a playlist
  Future<bool> deletePlaylist(String playlistId) async {
    if (!isAuthenticated) return false;

    final response = await _request('playlist/delete', {
      'playlistId': playlistId,
    }, authenticated: true);

    return response != null;
  }

  // ============ YOUTUBE MUSIC RADIO / WATCH PLAYLIST ============

  /// Get YouTube Music radio queue (Up Next) for a video
  /// This is the PROPER way to get radio - uses the "next" endpoint
  /// Returns tracks that YouTube Music would actually play in its queue
  Future<List<Track>> getWatchPlaylist(
    String videoId, {
    String? playlistId,
    int limit = 25,
  }) async {
    // Use the "next" endpoint which returns the watch queue
    // For radio mode, we need to provide a radio mix playlist ID
    // YouTube Music radio playlist IDs start with "RDAMVM" + videoId
    final radioPlaylistId = playlistId ?? 'RDAMVM$videoId';

    final body = <String, dynamic>{
      'videoId': videoId,
      'playlistId': radioPlaylistId,
      'isAudioOnly': true,
      'params': 'wAEB', // Parameter for autoplay/radio mode
    };

    if (kDebugMode) {
      print(
        'InnerTube: Fetching watch playlist for $videoId with playlist $radioPlaylistId',
      );
    }

    final response = await _request(
      'next',
      body,
      authenticated: isAuthenticated,
    );

    if (response == null) {
      if (kDebugMode) {
        print('InnerTube: getWatchPlaylist got null response');
      }
      return [];
    }
    return _parseWatchPlaylist(response, videoId, limit);
  }

  /// Parse the watch playlist response to extract tracks
  List<Track> _parseWatchPlaylist(
    Map<String, dynamic> response,
    String currentVideoId,
    int limit,
  ) {
    try {
      final tracks = <Track>[];

      // Debug: print top-level keys
      if (kDebugMode) {
        print('WatchPlaylist: Response keys: ${response.keys.toList()}');
      }

      // Navigate to playlist panel renderer
      // Path: contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer
      //       .watchNextTabbedResultsRenderer.tabs[0].tabRenderer.content
      //       .musicQueueRenderer.content.playlistPanelRenderer.contents
      final tabs =
          _navigateJson(response, [
                'contents',
                'singleColumnMusicWatchNextResultsRenderer',
                'tabbedRenderer',
                'watchNextTabbedResultsRenderer',
                'tabs',
              ])
              as List?;

      if (tabs == null || tabs.isEmpty) {
        if (kDebugMode) {
          print('WatchPlaylist: No tabs found in standard path');
        }
        // Try alternative path for continuationContents
        final continuationContents = response['continuationContents'];
        if (continuationContents != null) {
          final playlistPanelContinuation =
              continuationContents['playlistPanelContinuation'];
          if (playlistPanelContinuation != null) {
            final contents =
                playlistPanelContinuation['contents'] as List? ?? [];
            if (kDebugMode) {
              print(
                'WatchPlaylist: Found ${contents.length} items in continuation',
              );
            }
            for (final item in contents) {
              if (item['automixPreviewVideoRenderer'] != null) continue;
              final videoRenderer = item['playlistPanelVideoRenderer'];
              if (videoRenderer == null) continue;
              final track = _parsePlaylistPanelVideo(videoRenderer);
              if (track != null && track.id != currentVideoId) {
                tracks.add(track);
                if (tracks.length >= limit) break;
              }
            }
            return tracks;
          }
        }
        return [];
      }

      // Find the "Up Next" tab (usually first tab)
      Map<String, dynamic>? playlistPanel;
      for (final tab in tabs) {
        final content = tab['tabRenderer']?['content'];
        final musicQueueRenderer = content?['musicQueueRenderer'];
        if (musicQueueRenderer != null) {
          playlistPanel =
              musicQueueRenderer['content']?['playlistPanelRenderer'];
          break;
        }
      }

      if (playlistPanel == null) {
        if (kDebugMode) {
          print('WatchPlaylist: No playlist panel found');
        }
        return [];
      }

      final contents = playlistPanel['contents'] as List? ?? [];
      if (kDebugMode) {
        print('WatchPlaylist: Found ${contents.length} items in queue');
      }

      for (final item in contents) {
        // Skip the automix preview renderer (it's at the end for continuation)
        if (item['automixPreviewVideoRenderer'] != null) continue;

        final videoRenderer = item['playlistPanelVideoRenderer'];
        if (videoRenderer == null) continue;

        final track = _parsePlaylistPanelVideo(videoRenderer);
        if (track != null && track.id != currentVideoId) {
          tracks.add(track);
          if (tracks.length >= limit) break;
        }
      }

      if (kDebugMode) {
        print('WatchPlaylist: Parsed ${tracks.length} tracks');
      }
      return tracks;
    } catch (e, stack) {
      if (kDebugMode) {
        print('WatchPlaylist: Error parsing: $e');
      }
      if (kDebugMode) {
        print('WatchPlaylist: Stack: $stack');
      }
      return [];
    }
  }

  /// Parse a playlistPanelVideoRenderer into a Track
  Track? _parsePlaylistPanelVideo(Map<String, dynamic> renderer) {
    try {
      final videoId = renderer['videoId'] as String?;
      if (videoId == null) return null;

      // Get title
      final titleRuns = renderer['title']?['runs'] as List?;
      final title = titleRuns?.map((r) => r['text']).join() ?? 'Unknown';

      // Get artist and artistId from shortBylineText or longBylineText
      final artistRuns =
          renderer['shortBylineText']?['runs'] as List? ??
          renderer['longBylineText']?['runs'] as List?;
      String artist = 'Unknown Artist';
      String? artistId;
      if (artistRuns != null && artistRuns.isNotEmpty) {
        // Filter out non-artist parts (like " • " separators, views, etc.)
        final artistParts = artistRuns
            .where(
              (r) =>
                  r['navigationEndpoint']?['browseEndpoint'] != null ||
                  artistRuns.length == 1,
            )
            .toList();
        artist = artistParts.map((r) => r['text']).join(', ');
        if (artist.isEmpty) {
          artist = artistRuns[0]['text'] ?? 'Unknown Artist';
        }
        // Extract artistId from first artist with browse endpoint
        for (final run in artistRuns) {
          final browseEndpoint = run['navigationEndpoint']?['browseEndpoint'];
          if (browseEndpoint != null) {
            artistId = browseEndpoint['browseId'] as String?;
            break;
          }
        }
      }

      // Get duration
      final lengthText =
          renderer['lengthText']?['runs']?[0]?['text'] as String?;
      Duration duration = Duration.zero;
      if (lengthText != null) {
        duration = _parseDuration(lengthText);
      }

      // Get thumbnail
      final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      return Track(
        id: videoId,
        title: title,
        artist: artist,
        artistId: artistId ?? '',
        duration: duration,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      return null;
    }
  }

  // ============ SEARCH ============

  /// Search YouTube Music
  Future<SearchResults> search(String query, {String? filter}) async {
    final params = filter != null ? {'params': filter} : <String, String>{};

    final response = await _request('search', {
      'query': query,
      ...params,
    }, authenticated: isAuthenticated);

    if (response == null) return SearchResults.empty(query);
    return _parseSearchResults(response, query);
  }

  /// Get search suggestions
  Future<List<String>> getSearchSuggestions(String query) async {
    final response = await _request('music/get_search_suggestions', {
      'input': query,
    });

    if (response == null) return [];

    try {
      final contents = response['contents'] as List?;
      if (contents == null) return [];

      final suggestions = <String>[];
      for (final item in contents) {
        final runs =
            item['searchSuggestionsSectionRenderer']?['contents'] as List?;
        if (runs != null) {
          for (final run in runs) {
            final suggestion =
                run['searchSuggestionRenderer']?['suggestion']?['runs'];
            if (suggestion != null) {
              final text = (suggestion as List).map((r) => r['text']).join();
              suggestions.add(text);
            }
          }
        }
      }
      return suggestions;
    } catch (e) {
      return [];
    }
  }

  // ============ CONTENT ============

  /// Get playlist details
  Future<Playlist?> getPlaylist(String playlistId) async {
    String browseId = playlistId;
    if (!browseId.startsWith('VL')) {
      browseId = 'VL$playlistId';
    }

    final response = await _request('browse', {
      'browseId': browseId,
    }, authenticated: isAuthenticated);

    if (response == null) return null;

    // Parse first page
    final (playlist, continuation) = _parsePlaylistDetailsWithContinuation(
      response,
      playlistId,
    );
    if (playlist == null) return null;

    // Fetch remaining pages if there's a continuation
    String? nextContinuation = continuation;
    final allTracks = List<Track>.from(playlist.tracks ?? []);

    while (nextContinuation != null) {
      final contResponse = await _request('browse', {
        'continuation': nextContinuation,
      }, authenticated: isAuthenticated);

      if (contResponse == null) break;

      final (moreTracks, nextCont) = _parsePlaylistContinuation(contResponse);
      allTracks.addAll(moreTracks);
      nextContinuation = nextCont;
    }

    return Playlist(
      id: playlist.id,
      title: playlist.title,
      description: playlist.description,
      thumbnailUrl: playlist.thumbnailUrl,
      author: playlist.author,
      trackCount: allTracks.length,
      tracks: allTracks,
      isYTMusic: playlist.isYTMusic,
    );
  }

  /// Get album details
  Future<Album?> getAlbum(String albumId) async {
    final response = await _request('browse', {
      'browseId': albumId,
    }, authenticated: isAuthenticated);

    if (response == null) return null;
    return _parseAlbumDetails(response, albumId);
  }

  /// Get artist details
  Future<Artist?> getArtist(String channelId) async {
    final response = await _request('browse', {
      'browseId': channelId,
    }, authenticated: isAuthenticated);

    if (response == null) return null;
    return _parseArtistDetails(response, channelId);
  }

  /// Browse a shelf/section by its browseId (for "See all" / "More" navigation)
  /// Returns a list of HomeShelfItems with optional continuation token
  /// For artist songs, params must also be provided
  Future<BrowseShelfResult> browseShelf(
    String browseId, {
    String? continuationToken,
    String? params,
  }) async {
    Map<String, dynamic> body;
    if (continuationToken != null) {
      body = {'continuation': continuationToken};
    } else {
      body = {'browseId': browseId};
      if (params != null) {
        body['params'] = params;
      }
    }

    if (kDebugMode) {
      print(
        'BrowseShelf: browseId=$browseId, params=$params, continuation=${continuationToken != null}',
      );
    }

    final response = await _request(
      'browse',
      body,
      authenticated: isAuthenticated,
    );

    if (response == null) {
      if (kDebugMode) {
        print('BrowseShelf: Response is null');
      }
      return BrowseShelfResult(items: [], continuationToken: null);
    }

    return _parseBrowseShelfResult(response, browseId);
  }

  /// Get song/video details (for streaming URL)
  Future<Map<String, dynamic>?> getPlayer(String videoId) async {
    final response = await _request('player', {
      'videoId': videoId,
      'playlistId': null,
    }, authenticated: isAuthenticated);

    return response;
  }

  // Cache for player.js decryption function
  String? _cachedPlayerJs;
  List<String>? _cachedDecryptionSteps;

  // SharedPreferences keys for signature cipher persistence
  static const String _kDecryptionStepsKey = 'signature_decryption_steps';
  static const String _kDecryptionStepsCachedAtKey =
      'signature_decryption_cached_at';
  static const int _decryptionStepsTtlHours = 24;

  /// Decode a signatureCipher to get the actual stream URL
  Future<String?> _decodeSignatureCipher(String signatureCipher) async {
    try {
      // Parse the cipher parameters
      final params = Uri.splitQueryString(signatureCipher);
      final scrambledSig = params['s'];
      final sigParam = params['sp'] ?? 'signature';
      final baseUrl = params['url'];

      if (scrambledSig == null || baseUrl == null) {
        if (kDebugMode) {
          print('Auth: Invalid signatureCipher format');
        }
        return null;
      }

      // Get decryption steps from player.js
      final steps = await _getDecryptionSteps();
      if (steps == null || steps.isEmpty) {
        if (kDebugMode) {
          print('Auth: Could not get decryption steps');
        }
        return null;
      }

      // Apply decryption
      final decodedSig = _decryptSignature(scrambledSig, steps);

      // Build final URL
      final decodedUrl =
          '$baseUrl&$sigParam=${Uri.encodeComponent(decodedSig)}';
      return decodedUrl;
    } catch (e) {
      if (kDebugMode) {
        print('Auth: Signature decoding failed: $e');
      }
      return null;
    }
  }

  /// Get decryption steps from YouTube's player.js
  /// Persists to SharedPreferences for 24 hours
  Future<List<String>?> _getDecryptionSteps() async {
    // Check in-memory cache first
    if (_cachedDecryptionSteps != null) {
      return _cachedDecryptionSteps;
    }

    // Check SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStepsJson = prefs.getString(_kDecryptionStepsKey);
      final cachedAtStr = prefs.getString(_kDecryptionStepsCachedAtKey);

      if (cachedStepsJson != null && cachedAtStr != null) {
        final cachedAt = DateTime.tryParse(cachedAtStr);
        if (cachedAt != null) {
          final age = DateTime.now().difference(cachedAt);
          if (age.inHours < _decryptionStepsTtlHours) {
            final steps = (jsonDecode(cachedStepsJson) as List).cast<String>();
            if (steps.isNotEmpty) {
              if (kDebugMode) {
                print(
                  'Auth: Loaded ${steps.length} decryption steps from cache (${age.inMinutes}min old)',
                );
              }
              _cachedDecryptionSteps = steps;
              return steps;
            }
          } else {
            if (kDebugMode) {
              print(
                'Auth: Cached decryption steps expired (${age.inHours}h old)',
              );
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Auth: Failed to load cached decryption steps: $e');
      }
    }

    try {
      // First get the player.js URL from YouTube
      final embedResponse = await http
          .get(
            Uri.parse(
              'https://www.youtube.com/embed/dQw4w9WgXcQ',
            ), // Any video works
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // Find player.js URL
      final playerJsMatch = RegExp(
        r'"(/s/player/[^"]+/player_ias\.vflset/[^"]+/base\.js)"',
      ).firstMatch(embedResponse.body);

      if (playerJsMatch == null) {
        // Try alternative pattern
        final altMatch = RegExp(
          r'/s/player/([a-zA-Z0-9_-]+)/',
        ).firstMatch(embedResponse.body);
        if (altMatch == null) {
          if (kDebugMode) {
            print('Auth: Could not find player.js URL');
          }
          return null;
        }
      }

      final playerJsPath = playerJsMatch?.group(1) ?? '';
      final playerJsUrl = 'https://www.youtube.com$playerJsPath';

      if (kDebugMode) {
        print('Auth: Fetching player.js from $playerJsUrl');
      }

      // Fetch player.js
      final playerResponse = await http
          .get(
            Uri.parse(playerJsUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 15));

      _cachedPlayerJs = playerResponse.body;
      if (kDebugMode) {
        print('Auth: player.js length: ${_cachedPlayerJs!.length}');
      }

      // Debug: Search for signatureCipher handling code
      final sigCipherIdx = _cachedPlayerJs!.indexOf('signatureCipher');
      if (sigCipherIdx > 0) {
        if (kDebugMode) {
          print('Auth: signatureCipher found at $sigCipherIdx');
        }
      }

      // Try to find the actual sig decryption by looking for common patterns
      // Pattern: &&(c=XX(decodeURIComponent(c.s)),...)
      final sigHandlerMatch = RegExp(
        r'&&\s*\(\s*[a-z]\s*=\s*([a-zA-Z0-9$_]{2,})\s*\(\s*decodeURIComponent',
      ).firstMatch(_cachedPlayerJs!);
      if (sigHandlerMatch != null) {
        if (kDebugMode) {
          print(
            'Auth: Possible sig handler function: ${sigHandlerMatch.group(1)}',
          );
        }
      }

      // Extract decryption function
      _cachedDecryptionSteps = _extractDecryptionSteps(_cachedPlayerJs!);

      // Persist to SharedPreferences
      if (_cachedDecryptionSteps != null &&
          _cachedDecryptionSteps!.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _kDecryptionStepsKey,
            jsonEncode(_cachedDecryptionSteps),
          );
          await prefs.setString(
            _kDecryptionStepsCachedAtKey,
            DateTime.now().toIso8601String(),
          );
          if (kDebugMode) {
            print(
              'Auth: Persisted ${_cachedDecryptionSteps!.length} decryption steps to cache',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Auth: Failed to persist decryption steps: $e');
          }
        }
      }

      return _cachedDecryptionSteps;
    } catch (e) {
      if (kDebugMode) {
        print('Auth: Failed to get player.js: $e');
      }
      return null;
    }
  }

  /// Check if a name is a JavaScript built-in function
  bool _isBuiltIn(String name) {
    return [
      'encodeURIComponent',
      'decodeURIComponent',
      'escape',
      'unescape',
      'parseInt',
      'parseFloat',
      'String',
      'Number',
      'Array',
      'Object',
    ].contains(name);
  }

  /// Extract decryption steps from player.js
  List<String>? _extractDecryptionSteps(String playerJs) {
    try {
      // Find the signature decryption function name
      // YouTube's player uses various variable names (a, m, etc.) and patterns

      String? funcName;
      String? varName; // The variable name used in the function (a, m, etc.)

      // Look for the function that:
      // 1. Takes a single argument
      // 2. Splits it on ""
      // 3. Applies transformations
      // 4. Joins it back with ""

      // The signature decryption function pattern has evolved.
      // We need to find the function that's called when handling signatureCipher
      // Look for pattern like: c.set(b,encodeURIComponent(XX(decodeURIComponent(c.get("s")))))
      // or: XX(c)

      // Method 1: Look for the encodeURIComponent call site that references the sig decryption
      final encodePattern = RegExp(
        r'\b([a-zA-Z0-9$_]{2,})\s*\(\s*decodeURIComponent\s*\(\s*[a-zA-Z0-9$_]+\.get\s*\(\s*"s"\s*\)\s*\)\s*\)',
      );
      var encMatch = encodePattern.firstMatch(playerJs);
      if (encMatch != null) {
        final candidate = encMatch.group(1);
        if (candidate != null && !_isBuiltIn(candidate)) {
          funcName = candidate;
          if (kDebugMode) {
            print(
              'Auth: Found decryption function via encodeURIComponent pattern: $funcName',
            );
          }
        }
      }

      // Method 2: Look for pattern set(b,XX(YY)) where XX is the function
      if (funcName == null) {
        final setPattern = RegExp(
          r'\.set\s*\(\s*[a-zA-Z0-9$_]+\s*,\s*([a-zA-Z0-9$_]{2,})\s*\(\s*[a-zA-Z0-9$_]+\s*\)\s*\)',
        );
        for (final match in setPattern.allMatches(playerJs)) {
          final candidate = match.group(1);
          if (candidate != null &&
              !_isBuiltIn(candidate) &&
              candidate.length > 2) {
            // Verify this function has a.split("") pattern
            final funcPattern = RegExp(
              '${RegExp.escape(candidate)}\\s*=\\s*function\\s*\\(\\s*[a-z]\\s*\\)\\s*\\{[a-z]\\s*=\\s*[a-z]\\.split\\s*\\(\\s*""\\s*\\)',
            );
            if (funcPattern.hasMatch(playerJs)) {
              funcName = candidate;
              if (kDebugMode) {
                print(
                  'Auth: Found decryption function via set() pattern: $funcName',
                );
              }
              break;
            }
          }
        }
      }

      // Method 3: Find functions that use the helper object pattern
      // The signature function calls helper.method(a,N) multiple times
      if (funcName == null) {
        // First find a helper object with reverse/splice/swap methods
        final helperObjPattern = RegExp(
          r'var\s+([a-zA-Z0-9$_]{2,})\s*=\s*\{[^}]*(?:reverse|splice)[^}]*\}',
        );
        final helperMatch = helperObjPattern.firstMatch(playerJs);
        if (helperMatch != null) {
          final helperName = helperMatch.group(1)!;
          if (kDebugMode) {
            print('Auth: Found helper object: $helperName');
          }

          // Now find the function that uses this helper
          final escapedHelper = RegExp.escape(helperName);
          final userFuncPattern = RegExp(
            '([a-zA-Z0-9\$_]{2,})\\s*=\\s*function\\s*\\(\\s*([a-z])\\s*\\)\\s*\\{[a-z]\\s*=\\s*[a-z]\\.split\\s*\\(\\s*""\\s*\\)[^}]*$escapedHelper\\.[a-zA-Z0-9\$_]+[^}]*return\\s+[a-z]\\.join\\s*\\(\\s*""\\s*\\)',
          );
          final userMatch = userFuncPattern.firstMatch(playerJs);
          if (userMatch != null) {
            funcName = userMatch.group(1);
            varName = userMatch.group(2);
            if (kDebugMode) {
              print(
                'Auth: Found decryption function that uses helper: $funcName (var: $varName)',
              );
            }
          }
        }
      }

      // Debug: show some context around split patterns
      if (funcName == null) {
        // More permissive pattern - find ANY function with split and join
        // Pattern: funcName=function(x){x=x.split("");...return x.join("")}
        // With looser whitespace requirements

        // Try to find: =function(X){X=X.split("") where X is same var
        final splitPattern = RegExp(
          r'=\s*function\s*\(\s*([a-zA-Z])\s*\)\s*\{\s*\1\s*=\s*\1\s*\.\s*split\s*\(\s*""\s*\)',
        );
        final splitMatch = splitPattern.firstMatch(playerJs);

        if (splitMatch != null) {
          // Found the pattern, now find the function name before it
          final matchStart = splitMatch.start;
          final before = playerJs.substring(
            max(0, matchStart - 50),
            matchStart,
          );
          final nameMatch = RegExp(
            r'([a-zA-Z0-9$_]{2,})\s*$',
          ).firstMatch(before);
          if (nameMatch != null) {
            funcName = nameMatch.group(1);
            varName = splitMatch.group(1);
            if (kDebugMode) {
              print(
                'Auth: Found decryption function via split pattern: $funcName (var: $varName)',
              );
            }
          }
        }

        // If still not found, try an even simpler approach
        if (funcName == null) {
          // Search for pattern: XX.YY(a,N) which is the helper call pattern
          // First find a helper object with reverse/splice
          final helperPattern = RegExp(
            r'var\s+([a-zA-Z0-9$_]{2,})\s*=\s*\{[^}]*reverse[^}]*\}',
          );
          final helperMatch = helperPattern.firstMatch(playerJs);

          if (helperMatch != null) {
            final helperName = helperMatch.group(1)!;
            if (kDebugMode) {
              print('Auth: Found helper with reverse: $helperName');
            }

            // Now find the function that uses this helper
            final usePattern = RegExp(
              '([a-zA-Z0-9\$_]{2,})\\s*=\\s*function\\s*\\(\\s*([a-zA-Z])\\s*\\)[^{]*\\{[^}]*${RegExp.escape(helperName)}\\.',
            );
            final useMatch = usePattern.firstMatch(playerJs);
            if (useMatch != null) {
              funcName = useMatch.group(1);
              varName = useMatch.group(2);
              if (kDebugMode) {
                print(
                  'Auth: Found function using helper: $funcName (var: $varName)',
                );
              }
            }
          }
        }

        // Debug output
        if (funcName == null) {
          // Show raw patterns we're looking for
          final rawSplit = playerJs.indexOf('=function(a){a=a.split("")');
          if (kDebugMode) {
            print('Auth: Raw pattern 1 at: $rawSplit');
          }

          final rawSplit2 = playerJs.indexOf('.split("")');
          if (rawSplit2 > 0) {
            if (kDebugMode) {
              print('Auth: .split("") at $rawSplit2');
            }
            final ctx = playerJs.substring(
              max(0, rawSplit2 - 40),
              min(rawSplit2 + 20, playerJs.length),
            );
            if (kDebugMode) {
              print('Auth: Context: $ctx');
            }
          }
        }
      }

      // Alternative: search for the actual signature decryption call site
      // Pattern: .set("sig",encodeURIComponent(XX(YY.s)))
      // or: &&c.set(b,encodeURIComponent(XX(decodeURIComponent(c.get("s")))))
      if (funcName == null) {
        final callSitePattern = RegExp(
          r'[a-zA-Z0-9$_]+\.set\s*\([^,]+,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$_]{2,})\s*\([^)]+\)\s*\)',
        );
        final callMatch = callSitePattern.firstMatch(playerJs);
        if (callMatch != null) {
          final candidate = callMatch.group(1);
          if (candidate != null && !_isBuiltIn(candidate)) {
            funcName = candidate;
            if (kDebugMode) {
              print('Auth: Found decryption function via call site: $funcName');
            }
          }
        }
      }

      if (funcName == null) {
        if (kDebugMode) {
          print('Auth: Could not find decryption function name');
        }
        return null;
      }

      // Find the function body - handle any single-letter variable name
      final escapedName = RegExp.escape(funcName);

      // Pattern that captures: funcName=function(x){...return x.join("")}
      // Where x can be any single letter
      final funcBodyMatch = RegExp(
        '$escapedName\\s*=\\s*function\\s*\\(\\s*([a-zA-Z])\\s*\\)\\s*\\{(.+?)return\\s+\\1\\.join\\s*\\(\\s*""\\s*\\)',
        dotAll: true,
      ).firstMatch(playerJs);

      if (funcBodyMatch == null) {
        if (kDebugMode) {
          print('Auth: Could not find function body for $funcName');
        }
        // Debug: show what we're looking for
        final idx = playerJs.indexOf(funcName);
        if (idx >= 0) {
          if (kDebugMode) {
            print(
              'Auth: Found $funcName at index $idx, context: ${playerJs.substring(idx, min(idx + 100, playerJs.length))}...',
            );
          }
        }
        return null;
      }

      final actualVarName = funcBodyMatch.group(1)!;
      final funcBody = funcBodyMatch.group(2)!;
      if (kDebugMode) {
        print(
          'Auth: Found function body (var: $actualVarName, ${funcBody.length} chars)',
        );
      }
      return _parseDecryptionBody(funcBody, playerJs, actualVarName);
    } catch (e) {
      if (kDebugMode) {
        print('Auth: Failed to extract decryption steps: $e');
      }
      return null;
    }
  }

  /// Parse the function body to extract decryption steps
  List<String>? _parseDecryptionBody(
    String funcBody,
    String playerJs,
    String varName,
  ) {
    // Extract the helper object name (e.g., "Xo" in "Xo.rW(a,3)")
    // Use the actual variable name from the function
    final helperMatch = RegExp(
      '([a-zA-Z0-9\$_]{2,})\\.([a-zA-Z0-9\$_]+)\\s*\\(\\s*$varName\\s*,',
    ).firstMatch(funcBody);
    if (helperMatch == null) {
      if (kDebugMode) {
        print(
          'Auth: Could not find helper object in function body (looking for var: $varName)',
        );
      }
      if (kDebugMode) {
        print(
          'Auth: Function body sample: ${funcBody.substring(0, min(200, funcBody.length))}...',
        );
      }
      return null;
    }

    final helperName = helperMatch.group(1)!;
    if (kDebugMode) {
      print('Auth: Found helper object: $helperName');
    }

    // Find helper object definition
    final escapedHelper = RegExp.escape(helperName);
    final helperDefMatch = RegExp(
      'var $escapedHelper\\s*=\\s*\\{([\\s\\S]*?)\\};',
    ).firstMatch(playerJs);

    if (helperDefMatch == null) {
      if (kDebugMode) {
        print('Auth: Could not find helper object definition for $helperName');
      }
      return null;
    }

    final helperBody = helperDefMatch.group(1)!;
    if (kDebugMode) {
      print('Auth: Found helper object body (${helperBody.length} chars)');
    }

    // Parse helper methods
    final methods = <String, String>{};
    final methodMatches = RegExp(
      r'([a-zA-Z0-9$_]+)\s*:\s*function\s*\([^)]*\)\s*\{([^}]+)\}',
    ).allMatches(helperBody);

    for (final match in methodMatches) {
      final methodName = match.group(1)!;
      final methodBody = match.group(2)!;

      if (methodBody.contains('reverse')) {
        methods[methodName] = 'reverse';
      } else if (methodBody.contains('splice')) {
        methods[methodName] = 'splice';
      } else if (methodBody.contains('var c=') ||
          methodBody.contains('var c ')) {
        methods[methodName] = 'swap';
      }
    }

    if (kDebugMode) {
      print('Auth: Found ${methods.length} helper methods: $methods');
    }

    // Parse the main function calls - use the actual variable name
    final steps = <String>[];
    final callMatches = RegExp(
      '$escapedHelper\\.([a-zA-Z0-9\$_]+)\\s*\\(\\s*$varName\\s*,\\s*(\\d+)\\s*\\)',
    ).allMatches(funcBody);

    for (final match in callMatches) {
      final methodName = match.group(1)!;
      final param = match.group(2)!;
      final operation = methods[methodName];

      if (operation != null) {
        steps.add('$operation:$param');
      } else {
        if (kDebugMode) {
          print('Auth: Unknown method $methodName');
        }
      }
    }

    if (kDebugMode) {
      print('Auth: Extracted ${steps.length} decryption steps: $steps');
    }
    return steps.isNotEmpty ? steps : null;
  }

  /// Apply decryption steps to scrambled signature
  String _decryptSignature(String sig, List<String> steps) {
    var chars = sig.split('');

    for (final step in steps) {
      final parts = step.split(':');
      final operation = parts[0];
      final param = int.tryParse(parts[1]) ?? 0;

      switch (operation) {
        case 'reverse':
          chars = chars.reversed.toList();
          break;
        case 'splice':
          chars = chars.sublist(param);
          break;
        case 'swap':
          final temp = chars[0];
          chars[0] = chars[param % chars.length];
          chars[param % chars.length] = temp;
          break;
      }
    }

    return chars.join('');
  }

  /// Get audio stream URL for a video
  /// Tries authenticated request first if logged in, then embed, then InnerTube clients
  Future<String?> getStreamUrl(String videoId) async {
    if (kDebugMode) {
      print(
        'Stream: Getting URL for $videoId (authenticated: $isAuthenticated)',
      );
    }

    // If authenticated, try authenticated request first (most reliable)
    if (isAuthenticated) {
      final authUrl = await _getAuthenticatedStreamUrl(videoId);
      if (authUrl != null) {
        return authUrl;
      }
    }

    // Try embed approach (bypasses some bot protection)
    final embedUrl = await _getEmbedStreamUrl(videoId);
    if (embedUrl != null) {
      return embedUrl;
    }

    // Fallback to direct InnerTube (may fail with bot protection)
    return _getInnerTubeStreamUrl(videoId);
  }

  /// Get stream URL using authenticated YouTube Music request
  Future<String?> _getAuthenticatedStreamUrl(String videoId) async {
    if (kDebugMode) {
      print('Auth: Trying authenticated request...');
    }

    try {
      // Try ANDROID_MUSIC client first - it typically returns direct URLs
      final androidMusicResult = await _tryAndroidMusicClient(videoId);
      if (androidMusicResult != null) {
        return androidMusicResult;
      }

      // Fallback to WEB_REMIX client
      return await _tryWebRemixClient(videoId);
    } catch (e) {
      if (kDebugMode) {
        print('Auth: Failed: $e');
      }
      return null;
    }
  }

  /// Try ANDROID_MUSIC client (returns direct URLs)
  Future<String?> _tryAndroidMusicClient(String videoId) async {
    if (kDebugMode) {
      print('Auth: Trying IOS_MUSIC client...');
    }

    try {
      // Use IOS client - it typically returns direct URLs
      final url = Uri.parse(
        'https://music.youtube.com/youtubei/v1/player?key=$_apiKey',
      );

      final iosMusicContext = {
        'client': {
          'clientName': 'IOS_MUSIC',
          'clientVersion': '6.42',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone14,3',
          'hl': 'en',
          'gl': 'US',
          'osName': 'iOS',
          'osVersion': '17.2.1',
          'platform': 'MOBILE',
        },
        'user': {'lockedSafetyMode': false},
      };

      final response = await http
          .post(
            url,
            headers: _buildHeaders(authenticated: true),
            body: jsonEncode({
              'context': iosMusicContext,
              'videoId': videoId,
              'racyCheckOk': true,
              'contentCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final streamingData = data['streamingData'] as Map<String, dynamic>?;

        if (kDebugMode) {
          print('Auth: IOS_MUSIC: streamingData: ${streamingData != null}');
        }

        if (streamingData != null) {
          // Check for direct URLs (IOS clients usually have them)
          final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
          if (kDebugMode) {
            print(
              'Auth: IOS_MUSIC: adaptiveFormats: ${adaptiveFormats?.length}',
            );
          }

          if (adaptiveFormats != null) {
            final audioFormats = adaptiveFormats
                .where(
                  (f) =>
                      (f['mimeType'] as String?)?.startsWith('audio/') == true,
                )
                .toList();

            if (kDebugMode) {
              print('Auth: IOS_MUSIC: audioFormats: ${audioFormats.length}');
            }

            if (audioFormats.isNotEmpty) {
              audioFormats.sort(
                (a, b) => (b['bitrate'] as int? ?? 0).compareTo(
                  a['bitrate'] as int? ?? 0,
                ),
              );

              final format = audioFormats.first;
              final directUrl = format['url'] as String?;
              final hasCipher = format['signatureCipher'] != null;

              if (kDebugMode) {
                print(
                  'Auth: IOS_MUSIC: hasDirectUrl: ${directUrl != null}, hasCipher: $hasCipher',
                );
              }

              if (directUrl != null) {
                if (kDebugMode) {
                  print(
                    'Auth: IOS_MUSIC: Got direct audio URL (${format['bitrate']} bps)',
                  );
                }
                return directUrl;
              }
            }
          }

          final formats = streamingData['formats'] as List?;
          if (formats != null) {
            for (final format in formats) {
              final directUrl = format['url'] as String?;
              if (directUrl != null) {
                if (kDebugMode) {
                  print('Auth: IOS_MUSIC: Got direct muxed URL');
                }
                return directUrl;
              }
            }
          }
        }

        final playability = data['playabilityStatus'] as Map?;
        if (kDebugMode) {
          print(
            'Auth: IOS_MUSIC status: ${playability?['status']} - ${playability?['reason'] ?? ''}',
          );
        }
      } else {
        if (kDebugMode) {
          print('Auth: IOS_MUSIC: HTTP ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Auth: IOS_MUSIC failed: $e');
      }
    }

    return null;
  }

  /// Try WEB_REMIX client (may return signatureCipher)
  Future<String?> _tryWebRemixClient(String videoId) async {
    if (kDebugMode) {
      print('Auth: Trying WEB_REMIX client...');
    }

    try {
      // First, get the signatureTimestamp from embed page
      int sts = 20073; // Default fallback
      try {
        final embedResponse = await http
            .get(
              Uri.parse('https://www.youtube.com/embed/$videoId'),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
            )
            .timeout(const Duration(seconds: 10));

        final stsMatch = RegExp(
          r'"sts"\s*:\s*(\d+)',
        ).firstMatch(embedResponse.body);
        if (stsMatch != null) {
          sts = int.tryParse(stsMatch.group(1)!) ?? sts;
          if (kDebugMode) {
            print('Auth: Using signatureTimestamp: $sts');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Auth: Could not get STS, using default: $sts');
        }
      }

      final url = Uri.parse('$_baseUrl/player?key=$_apiKey');

      final response = await http
          .post(
            url,
            headers: _buildHeaders(authenticated: true),
            body: jsonEncode({
              'context': _clientContext,
              'videoId': videoId,
              'playbackContext': {
                'contentPlaybackContext': {'signatureTimestamp': sts},
              },
              'racyCheckOk': true,
              'contentCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final streamingData = data['streamingData'] as Map<String, dynamic>?;

        if (kDebugMode) {
          print('Auth: streamingData keys: ${streamingData?.keys.toList()}');
        }

        if (streamingData != null) {
          // Try adaptive formats first (audio only)
          final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
          if (kDebugMode) {
            print('Auth: adaptiveFormats count: ${adaptiveFormats?.length}');
          }

          if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
            // Find best audio stream
            final audioFormats = adaptiveFormats
                .where(
                  (f) =>
                      (f['mimeType'] as String?)?.startsWith('audio/') == true,
                )
                .toList();

            if (kDebugMode) {
              print('Auth: audioFormats count: ${audioFormats.length}');
            }

            if (audioFormats.isNotEmpty) {
              // Sort by bitrate (highest first)
              audioFormats.sort(
                (a, b) => (b['bitrate'] as int? ?? 0).compareTo(
                  a['bitrate'] as int? ?? 0,
                ),
              );

              final format = audioFormats.first;

              // Check for direct URL first
              final url = format['url'] as String?;
              if (url != null) {
                if (kDebugMode) {
                  print('Auth: Got audio stream (${format['bitrate']} bps)');
                }
                return url;
              }

              // Handle signatureCipher - decode and return URL
              final signatureCipher = format['signatureCipher'] as String?;
              if (signatureCipher != null) {
                final decodedUrl = await _decodeSignatureCipher(
                  signatureCipher,
                );
                if (decodedUrl != null) {
                  if (kDebugMode) {
                    print(
                      'Auth: Got decoded audio stream (${format['bitrate']} bps)',
                    );
                  }
                  return decodedUrl;
                }
              }
            }
          }

          // Try formats (muxed streams)
          final formats = streamingData['formats'] as List?;
          if (formats != null && formats.isNotEmpty) {
            for (final format in formats) {
              final url = format['url'] as String?;
              if (url != null) {
                if (kDebugMode) {
                  print('Auth: Got muxed stream');
                }
                return url;
              }

              // Handle signatureCipher for muxed formats too
              final signatureCipher = format['signatureCipher'] as String?;
              if (signatureCipher != null) {
                final decodedUrl = await _decodeSignatureCipher(
                  signatureCipher,
                );
                if (decodedUrl != null) {
                  if (kDebugMode) {
                    print('Auth: Got decoded muxed stream');
                  }
                  return decodedUrl;
                }
              }
            }
          }

          // Try HLS manifest
          final hlsUrl = streamingData['hlsManifestUrl'] as String?;
          if (hlsUrl != null) {
            if (kDebugMode) {
              print('Auth: Got HLS manifest');
            }
            return hlsUrl;
          }
        } else {
          if (kDebugMode) {
            print('Auth: No streamingData in response');
          }
        }

        final playabilityStatus = data['playabilityStatus'] as Map?;
        final status = playabilityStatus?['status'] as String?;
        final reason =
            playabilityStatus?['reason'] as String? ??
            playabilityStatus?['messages']?.first as String? ??
            '';
        if (kDebugMode) {
          print('Auth: WEB_REMIX status: $status - $reason');
        }
      } else {
        if (kDebugMode) {
          print('Auth: WEB_REMIX request failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Auth: WEB_REMIX failed: $e');
      }
    }

    return null;
  }

  /// Get stream URL using YouTube embed approach
  Future<String?> _getEmbedStreamUrl(String videoId) async {
    if (kDebugMode) {
      print('Embed: Trying embed approach...');
    }

    try {
      // First, get the embed page to extract config
      final embedUrl = 'https://www.youtube.com/embed/$videoId';
      final embedResponse = await http
          .get(
            Uri.parse(embedUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.5',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (embedResponse.statusCode != 200) {
        if (kDebugMode) {
          print('Embed: Failed to get embed page: ${embedResponse.statusCode}');
        }
        return null;
      }

      // Extract the sts (signature timestamp) from embed page
      final body = embedResponse.body;
      final stsMatch = RegExp(r'"sts"\s*:\s*(\d+)').firstMatch(body);
      final sts = stsMatch?.group(1) ?? '20073';
      if (kDebugMode) {
        print('Embed: Got sts=$sts');
      }

      // Now make the player request with TV client (works better for embeds)
      final playerUrl = Uri.parse(
        'https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8',
      );

      final playerResponse = await http
          .post(
            playerUrl,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
              'Origin': 'https://www.youtube.com',
              'Referer': 'https://www.youtube.com/embed/$videoId',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
                  'clientVersion': '2.0',
                  'hl': 'en',
                  'gl': 'US',
                  'clientScreen': 'EMBED',
                },
                'thirdParty': {
                  'embedUrl': 'https://www.youtube.com/embed/$videoId',
                },
              },
              'videoId': videoId,
              'playbackContext': {
                'contentPlaybackContext': {
                  'signatureTimestamp': int.tryParse(sts) ?? 20073,
                  'html5Preference': 'HTML5_PREF_WANTS',
                },
              },
              'racyCheckOk': true,
              'contentCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (playerResponse.statusCode == 200) {
        final data = jsonDecode(playerResponse.body) as Map<String, dynamic>;
        final streamingData = data['streamingData'] as Map<String, dynamic>?;

        if (streamingData != null) {
          // Try adaptive formats first (audio only)
          final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
          if (adaptiveFormats != null) {
            for (final format in adaptiveFormats) {
              final mimeType = format['mimeType'] as String? ?? '';
              if (mimeType.startsWith('audio/')) {
                final url = format['url'] as String?;
                if (url != null) {
                  if (kDebugMode) {
                    print('Embed: Got audio stream');
                  }
                  return url;
                }
              }
            }
          }

          // Try HLS
          final hlsUrl = streamingData['hlsManifestUrl'] as String?;
          if (hlsUrl != null) {
            if (kDebugMode) {
              print('Embed: Got HLS manifest');
            }
            return hlsUrl;
          }
        }

        final playabilityStatus = data['playabilityStatus'] as Map?;
        final status = playabilityStatus?['status'] as String?;
        final reason =
            playabilityStatus?['reason'] as String? ??
            playabilityStatus?['messages']?.first as String? ??
            'Unknown';
        if (kDebugMode) {
          print('Embed: Playability status: $status - $reason');
        }
      } else {
        if (kDebugMode) {
          print('Embed: Player request failed: ${playerResponse.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Embed: Failed: $e');
      }
    }

    return null;
  }

  /// Get stream URL directly from InnerTube (may fail with bot protection)
  Future<String?> _getInnerTubeStreamUrl(String videoId) async {
    if (kDebugMode) {
      print('InnerTube: Trying direct API...');
    }

    // Try clients in order of reliability (based on OuterTune's findings)
    final clients = [
      // ANDROID_VR - Most reliable currently
      {
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.57.29',
            'androidSdkVersion': 30,
            'osName': 'Android',
            'osVersion': '12',
            'platform': 'MOBILE',
            'hl': 'en',
            'gl': 'US',
          },
          'user': {'lockedSafetyMode': false},
        },
        'headers': {
          'User-Agent':
              'com.google.android.apps.youtube.vr.oculus/1.57.29 (Linux; U; Android 12; Quest 2) gzip',
          'X-YouTube-Client-Name': '28',
          'X-YouTube-Client-Version': '1.57.29',
        },
      },
      // ANDROID_TESTSUITE - Good fallback
      {
        'context': {
          'client': {
            'clientName': 'ANDROID_TESTSUITE',
            'clientVersion': '1.9',
            'androidSdkVersion': 30,
            'osName': 'Android',
            'osVersion': '11',
            'platform': 'MOBILE',
            'hl': 'en',
            'gl': 'US',
          },
          'user': {'lockedSafetyMode': false},
        },
        'headers': {
          'User-Agent':
              'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
          'X-YouTube-Client-Name': '30',
          'X-YouTube-Client-Version': '1.9',
        },
      },
      // TV_EMBEDDED - Another fallback
      {
        'context': {
          'client': {
            'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
            'clientVersion': '2.0',
            'platform': 'TV',
            'hl': 'en',
            'gl': 'US',
          },
          'thirdParty': {'embedUrl': 'https://www.youtube.com'},
          'user': {'lockedSafetyMode': false},
        },
        'headers': {
          'User-Agent':
              'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 SmartHub/2021 TV Safari/538.1',
          'X-YouTube-Client-Name': '85',
          'X-YouTube-Client-Version': '2.0',
        },
      },
      // IOS - Last resort
      {
        'context': {
          'client': {
            'clientName': 'IOS',
            'clientVersion': '19.09.3',
            'deviceModel': 'iPhone14,3',
            'osName': 'iOS',
            'osVersion': '17.4.1',
            'hl': 'en',
            'gl': 'US',
          },
          'user': {'lockedSafetyMode': false},
        },
        'headers': {
          'User-Agent':
              'com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 17_4_1 like Mac OS X)',
          'X-YouTube-Client-Name': '5',
          'X-YouTube-Client-Version': '19.09.3',
        },
      },
    ];

    for (var i = 0; i < clients.length; i++) {
      final client = clients[i];
      final clientName = (client['context'] as Map)['client']['clientName'];
      if (kDebugMode) {
        print('InnerTube: Trying client $clientName...');
      }

      try {
        final url = Uri.parse(
          'https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8&prettyPrint=false',
        );

        final headers = {
          'Content-Type': 'application/json',
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
          ...(client['headers'] as Map<String, String>),
        };

        final body = {
          'context': client['context'],
          'videoId': videoId,
          'playbackContext': {
            'contentPlaybackContext': {
              'signatureTimestamp': 20073, // This may need updating
            },
          },
          'racyCheckOk': true,
          'contentCheckOk': true,
        };

        final response = await http.post(
          url,
          headers: headers,
          body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          // Check playability
          final playabilityStatus = data['playabilityStatus'];
          if (playabilityStatus != null) {
            final status = playabilityStatus['status'];
            if (kDebugMode) {
              print('InnerTube: $clientName playability status: $status');
            }

            if (status != 'OK') {
              final reason = playabilityStatus['reason'] ?? 'Unknown';
              if (kDebugMode) {
                print('InnerTube: $clientName blocked: $reason');
              }
              continue; // Try next client
            }
          }

          final streamUrl = _extractStreamUrl(data);
          if (streamUrl != null) {
            if (kDebugMode) {
              print('InnerTube: Got stream URL from $clientName');
            }
            return streamUrl;
          } else {
            if (kDebugMode) {
              print(
                'InnerTube: $clientName returned OK but no stream URL found',
              );
            }
          }
        } else {
          if (kDebugMode) {
            print('InnerTube: $clientName HTTP ${response.statusCode}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('InnerTube: $clientName error: $e');
        }
      }
    }

    if (kDebugMode) {
      print('InnerTube: All clients failed for $videoId');
    }
    return null;
  }

  /// Extract best audio stream URL from player response
  String? _extractStreamUrl(Map<String, dynamic> playerResponse) {
    try {
      final streamingData = playerResponse['streamingData'];
      if (streamingData == null) {
        if (kDebugMode) {
          print('InnerTube: No streamingData in response');
        }
        return null;
      }

      // Try adaptive formats first (audio-only, better quality)
      final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
      if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
        if (kDebugMode) {
          print('InnerTube: Found ${adaptiveFormats.length} adaptive formats');
        }

        // Find audio-only streams
        final audioStreams = adaptiveFormats.where((f) {
          final mimeType = f['mimeType']?.toString() ?? '';
          return mimeType.startsWith('audio/');
        }).toList();

        if (kDebugMode) {
          print('InnerTube: Found ${audioStreams.length} audio streams');
        }

        if (audioStreams.isNotEmpty) {
          // Sort by bitrate (highest first)
          audioStreams.sort(
            (a, b) => (b['bitrate'] as int? ?? 0).compareTo(
              a['bitrate'] as int? ?? 0,
            ),
          );

          for (final stream in audioStreams) {
            // Direct URL (preferred)
            if (stream['url'] != null) {
              final url = stream['url'] as String;
              if (kDebugMode) {
                print(
                  'InnerTube: Using direct URL, bitrate: ${stream['bitrate']}',
                );
              }
              return url;
            }

            // Signature cipher (needs decoding - skip for now)
            if (stream['signatureCipher'] != null) {
              if (kDebugMode) {
                print(
                  'InnerTube: Stream has signatureCipher (not supported yet)',
                );
              }
              continue;
            }
          }
        }
      }

      // Fallback to regular formats (muxed audio+video)
      final formats = streamingData['formats'] as List?;
      if (formats != null && formats.isNotEmpty) {
        if (kDebugMode) {
          print('InnerTube: Trying ${formats.length} muxed formats');
        }
        for (final format in formats) {
          if (format['url'] != null) {
            if (kDebugMode) {
              print('InnerTube: Using muxed format');
            }
            return format['url'] as String;
          }
        }
      }

      // Try HLS manifest as last resort
      final hlsUrl = streamingData['hlsManifestUrl'] as String?;
      if (hlsUrl != null) {
        if (kDebugMode) {
          print('InnerTube: Using HLS manifest');
        }
        return hlsUrl;
      }

      if (kDebugMode) {
        print('InnerTube: No usable stream URL found');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('InnerTube: Error extracting stream URL: $e');
      }
      return null;
    }
  }

  // ============ PARSERS ============

  /// Parse library tracks with continuation token from initial browse response
  (List<Track>, String?) _parseLibraryTracksWithContinuation(
    Map<String, dynamic> response,
  ) {
    final tracks = <Track>[];
    String? continuation;

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return ([], null);

      for (final section in contents) {
        final musicShelf = section['musicShelfRenderer'];
        if (musicShelf != null) {
          final items = musicShelf['contents'] as List?;
          if (items != null) {
            for (final item in items) {
              final track = _parseTrackItem(item);
              if (track != null) tracks.add(track);
            }
          }

          // Get continuation token
          final continuations = musicShelf['continuations'] as List?;
          if (continuations != null && continuations.isNotEmpty) {
            continuation =
                continuations[0]['nextContinuationData']?['continuation']
                    as String?;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library tracks with continuation: $e');
      }
    }

    return (tracks, continuation);
  }

  /// Parse continuation response for library tracks
  (List<Track>, String?) _parseLibraryContinuation(
    Map<String, dynamic> response,
  ) {
    final tracks = <Track>[];
    String? continuation;

    try {
      final continuationContents =
          response['continuationContents']?['musicShelfContinuation'];
      if (continuationContents != null) {
        final items = continuationContents['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final track = _parseTrackItem(item);
            if (track != null) tracks.add(track);
          }
        }

        // Debug: Print all keys in musicShelfContinuation
        if (kDebugMode) {
          print(
            'LikedSongs: musicShelfContinuation keys: ${(continuationContents as Map).keys.toList()}',
          );
        }

        // Get next continuation token - try multiple possible locations
        final continuations = continuationContents['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          if (kDebugMode) {
            print(
              'LikedSongs: continuations[0] keys: ${(continuations[0] as Map).keys.toList()}',
            );
          }
          // Try nextContinuationData first
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
          // Also try reloadContinuationData
          continuation ??=
              continuations[0]['reloadContinuationData']?['continuation']
                  as String?;
        } else {
          if (kDebugMode) {
            print('LikedSongs: No continuations array found');
          }
        }
      } else {
        // Try alternative structure
        final sectionListContinuation =
            response['continuationContents']?['sectionListContinuation'];
        if (sectionListContinuation != null) {
          if (kDebugMode) {
            print('LikedSongs: Found sectionListContinuation instead');
          }
          final contents = sectionListContinuation['contents'] as List?;
          if (contents != null) {
            for (final section in contents) {
              final items = section['musicShelfRenderer']?['contents'] as List?;
              if (items != null) {
                for (final item in items) {
                  final track = _parseTrackItem(item);
                  if (track != null) tracks.add(track);
                }
              }
            }
          }
          final continuations =
              sectionListContinuation['continuations'] as List?;
          if (continuations != null && continuations.isNotEmpty) {
            continuation =
                continuations[0]['nextContinuationData']?['continuation']
                    as String?;
            continuation ??=
                continuations[0]['reloadContinuationData']?['continuation']
                    as String?;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library continuation: $e');
      }
    }

    return (tracks, continuation);
  }

  List<Track> _parseLibraryTracks(Map<String, dynamic> response) {
    final tracks = <Track>[];

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return [];

      for (final section in contents) {
        final items = section['musicShelfRenderer']?['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final track = _parseTrackItem(item);
            if (track != null) tracks.add(track);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library tracks: $e');
      }
    }

    return tracks;
  }

  List<Track> _parseHistoryTracks(Map<String, dynamic> response) {
    final tracks = <Track>[];

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return [];

      for (final section in contents) {
        final items = section['musicShelfRenderer']?['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final track = _parseTrackItem(item);
            if (track != null) tracks.add(track);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing history tracks: $e');
      }
    }

    return tracks;
  }

  Track? _parseTrackItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Get video ID
      final overlay = renderer['overlay']?['musicItemThumbnailOverlayRenderer'];
      final playEndpoint =
          overlay?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
      final videoId = playEndpoint?['watchEndpoint']?['videoId'] as String?;

      if (videoId == null) return null;

      // Get title
      final titleRuns =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
              as List?;
      final title = titleRuns?.map((r) => r['text']).join() ?? 'Unknown';

      // Get artist and artistId from second flex column
      String artist = 'Unknown Artist';
      String? artistId;
      Duration? duration;

      if (flexColumns.length > 1) {
        final subtitleRuns =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          // First run is usually the artist name
          artist = subtitleRuns[0]['text'] ?? 'Unknown Artist';
          // Extract artistId from browse endpoint
          final browseEndpoint =
              subtitleRuns[0]['navigationEndpoint']?['browseEndpoint'];
          artistId = browseEndpoint?['browseId'] as String?;

          // Duration is often the last item in subtitle runs (format: "Artist • Album • 3:45")
          // Look for duration pattern in the runs
          for (final run in subtitleRuns.reversed) {
            final text = run['text'] as String?;
            if (text != null &&
                RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(text.trim())) {
              duration = _parseDuration(text.trim());
              break;
            }
          }
        }
      }

      // Get thumbnail
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      // Get duration from fixedColumns if not found in subtitle
      if (duration == null) {
        final fixedColumns = renderer['fixedColumns'] as List?;
        if (fixedColumns != null && fixedColumns.isNotEmpty) {
          final durationText =
              fixedColumns[0]['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text']
                  as String?;
          if (durationText != null) {
            duration = _parseDuration(durationText);
          }
        }
      }

      return Track(
        id: videoId,
        title: title,
        artist: artist,
        artistId: artistId ?? '',
        thumbnailUrl: thumbnailUrl,
        duration: duration ?? Duration.zero,
        isLiked: true,
      );
    } catch (e) {
      return null;
    }
  }

  List<Album> _parseLibraryAlbums(Map<String, dynamic> response) {
    final albums = <Album>[];

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return [];

      for (final section in contents) {
        final items =
            section['gridRenderer']?['items'] as List? ??
            section['musicShelfRenderer']?['contents'] as List?;

        if (items != null) {
          for (final item in items) {
            final album = _parseAlbumItem(item);
            if (album != null) albums.add(album);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library albums: $e');
      }
    }

    return albums;
  }

  Album? _parseAlbumItem(Map<String, dynamic> item) {
    try {
      final renderer =
          item['musicTwoRowItemRenderer'] ??
          item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Get browse ID
      final browseEndpoint = renderer['navigationEndpoint']?['browseEndpoint'];
      final albumId = browseEndpoint?['browseId'] as String?;
      if (albumId == null) return null;

      // Check if this is actually an album (browseId should start with MPREb)
      if (!albumId.startsWith('MPREb')) return null;

      String title = 'Unknown Album';
      String artist = 'Unknown Artist';
      String? thumbnailUrl;

      // Handle musicTwoRowItemRenderer (grid view)
      if (item['musicTwoRowItemRenderer'] != null) {
        title =
            renderer['title']?['runs']?[0]?['text'] as String? ??
            'Unknown Album';

        final subtitle = renderer['subtitle']?['runs'] as List?;
        if (subtitle != null && subtitle.isNotEmpty) {
          // Skip type indicators like "Album" or "Single" and find artist name
          for (final run in subtitle) {
            final text = run['text'] as String?;
            if (text != null &&
                text != ' • ' &&
                text != 'Album' &&
                text != 'Single' &&
                text != 'EP' &&
                !RegExp(r'^\d{4}$').hasMatch(text)) {
              // Skip year
              artist = text;
              break;
            }
          }
        }

        final thumbnails =
            renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnailUrl = thumbnails.last['url'] as String?;
        }
      }
      // Handle musicResponsiveListItemRenderer (list view in search results)
      else if (item['musicResponsiveListItemRenderer'] != null) {
        final flexColumns = renderer['flexColumns'] as List?;
        if (flexColumns != null && flexColumns.isNotEmpty) {
          // Title is in first flex column
          final titleRuns =
              flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                  as List?;
          if (titleRuns != null && titleRuns.isNotEmpty) {
            title = titleRuns.map((r) => r['text']).join();
          }

          // Artist is in second flex column
          if (flexColumns.length > 1) {
            final subtitleRuns =
                flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                    as List?;
            if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
              // Find artist name - skip type indicators and separators
              for (final run in subtitleRuns) {
                final text = run['text'] as String?;
                if (text != null &&
                    text != ' • ' &&
                    text != 'Album' &&
                    text != 'Single' &&
                    text != 'EP' &&
                    !RegExp(r'^\d{4}$').hasMatch(text)) {
                  artist = text;
                  break;
                }
              }
            }
          }
        }

        final thumbnails =
            renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnailUrl = thumbnails.last['url'] as String?;
        }
      }

      return Album(
        id: albumId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      return null;
    }
  }

  List<Playlist> _parseLibraryPlaylists(Map<String, dynamic> response) {
    final playlists = <Playlist>[];

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return [];

      for (final section in contents) {
        final items =
            section['gridRenderer']?['items'] as List? ??
            section['musicShelfRenderer']?['contents'] as List?;

        if (items != null) {
          for (final item in items) {
            final playlist = _parsePlaylistItem(item);
            if (playlist != null) playlists.add(playlist);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library playlists: $e');
      }
    }

    return playlists;
  }

  Playlist? _parsePlaylistItem(Map<String, dynamic> item) {
    try {
      final renderer =
          item['musicTwoRowItemRenderer'] ??
          item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Get playlist ID
      final browseEndpoint = renderer['navigationEndpoint']?['browseEndpoint'];
      var playlistId = browseEndpoint?['browseId'] as String?;
      if (playlistId == null) return null;

      // Must be a playlist (VL prefix) or RDCLAK (radio)
      if (!playlistId.startsWith('VL') && !playlistId.startsWith('RDCLAK')) {
        return null;
      }

      // Remove VL prefix if present
      if (playlistId.startsWith('VL')) {
        playlistId = playlistId.substring(2);
      }

      // Get title from flexColumns or title field
      String? title;
      String? author;
      int trackCount = 0;

      // Try flexColumns first (search results use this)
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns != null && flexColumns.isNotEmpty) {
        // First column is title
        title =
            _navigateJson(flexColumns[0], [
                  'musicResponsiveListItemFlexColumnRenderer',
                  'text',
                  'runs',
                  0,
                  'text',
                ])
                as String?;

        // Second column has author and track count
        if (flexColumns.length > 1) {
          final subtitleRuns =
              _navigateJson(flexColumns[1], [
                    'musicResponsiveListItemFlexColumnRenderer',
                    'text',
                    'runs',
                  ])
                  as List?;

          if (subtitleRuns != null) {
            final subtitleText = subtitleRuns.map((r) => r['text']).join();
            // Parse author (usually first part before •)
            if (subtitleRuns.isNotEmpty) {
              author = subtitleRuns[0]['text'] as String?;
              // Remove "Playlist" prefix if present
              if (author == 'Playlist') {
                author = subtitleRuns.length > 2
                    ? subtitleRuns[2]['text'] as String?
                    : null;
              }
            }
            // Parse track count
            final countMatch = RegExp(
              r'(\d+)\s*(song|track|video)',
              caseSensitive: false,
            ).firstMatch(subtitleText);
            if (countMatch != null) {
              trackCount = int.tryParse(countMatch.group(1)!) ?? 0;
            }
          }
        }
      }

      // Fallback to title field
      title ??= renderer['title']?['runs']?[0]?['text'] as String?;
      if (title == null || title == 'Unknown Playlist') {
        return null; // Skip invalid playlists
      }

      // Get thumbnail
      final thumbnails =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      // Fallback track count from subtitle
      if (trackCount == 0) {
        final subtitle = renderer['subtitle']?['runs'] as List?;
        if (subtitle != null) {
          for (final run in subtitle) {
            final text = run['text'] as String?;
            if (text != null) {
              final match = RegExp(
                r'(\d+)\s*(song|track|video)?',
                caseSensitive: false,
              ).firstMatch(text);
              if (match != null) {
                trackCount = int.tryParse(match.group(1)!) ?? 0;
                if (trackCount > 0) break;
              }
            }
          }
        }
      }

      return Playlist(
        id: playlistId,
        title: title,
        thumbnailUrl: thumbnailUrl,
        trackCount: trackCount,
        author: author,
        isYTMusic: true,
      );
    } catch (e) {
      return null;
    }
  }

  List<Artist> _parseLibraryArtists(Map<String, dynamic> response) {
    final artists = <Artist>[];

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return [];

      for (final section in contents) {
        final items = section['musicShelfRenderer']?['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final artist = _parseArtistItem(item);
            if (artist != null) artists.add(artist);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing library artists: $e');
      }
    }

    return artists;
  }

  Artist? _parseArtistItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Get channel ID from navigation endpoint
      final browseEndpoint = renderer['navigationEndpoint']?['browseEndpoint'];
      final channelId = browseEndpoint?['browseId'] as String?;

      // Artists have channel IDs starting with UC (channels)
      if (channelId == null || !channelId.startsWith('UC')) return null;

      // Get name from flex columns
      final flexColumns = renderer['flexColumns'] as List?;
      String name = 'Unknown Artist';

      if (flexColumns != null && flexColumns.isNotEmpty) {
        final nameRuns =
            flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (nameRuns != null && nameRuns.isNotEmpty) {
          name = nameRuns[0]['text'] ?? 'Unknown Artist';
        }
      }

      // Get thumbnail
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      return Artist(
        id: channelId,
        name: name,
        thumbnailUrl: thumbnailUrl,
        isSubscribed: true,
      );
    } catch (e) {
      return null;
    }
  }

  SearchResults _parseSearchResults(
    Map<String, dynamic> response,
    String query,
  ) {
    final tracks = <Track>[];
    final albums = <Album>[];
    final artists = <Artist>[];
    final playlists = <Playlist>[];
    SearchResultItem? topResult;

    try {
      final contents =
          _navigateJson(response, [
                'contents',
                'tabbedSearchResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (contents == null) return SearchResults.empty(query);

      bool isFirstShelf = true;
      for (final section in contents) {
        // Check for top result card (musicCardShelfRenderer)
        final cardShelf = section['musicCardShelfRenderer'];
        if (cardShelf != null && topResult == null) {
          topResult = _parseTopResultCard(cardShelf);
          continue;
        }

        final shelf = section['musicShelfRenderer'];
        if (shelf == null) continue;

        final items = shelf['contents'] as List?;
        if (items == null) continue;

        // Track the first item of the first shelf as a fallback top result
        bool firstItemInShelf = isFirstShelf;
        isFirstShelf = false;

        for (final item in items) {
          final track = _parseTrackItem(item);
          if (track != null) {
            tracks.add(track);
            // Use first track as top result if no card shelf
            if (firstItemInShelf && topResult == null) {
              topResult = SearchResultItem.track(track);
              firstItemInShelf = false;
            }
            continue;
          }

          final album = _parseAlbumItem(item);
          if (album != null) {
            albums.add(album);
            if (firstItemInShelf && topResult == null) {
              topResult = SearchResultItem.album(album);
              firstItemInShelf = false;
            }
            continue;
          }

          final artist = _parseArtistItem(item);
          if (artist != null) {
            artists.add(artist);
            if (firstItemInShelf && topResult == null) {
              topResult = SearchResultItem.artist(artist);
              firstItemInShelf = false;
            }
            continue;
          }

          final playlist = _parsePlaylistItem(item);
          if (playlist != null) {
            playlists.add(playlist);
            if (firstItemInShelf && topResult == null) {
              topResult = SearchResultItem.playlist(playlist);
              firstItemInShelf = false;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing search results: $e');
      }
    }

    return SearchResults(
      query: query,
      tracks: tracks,
      albums: albums,
      artists: artists,
      playlists: playlists,
      topResult: topResult,
    );
  }

  /// Parse the top result card from YouTube Music search
  SearchResultItem? _parseTopResultCard(Map<String, dynamic> cardShelf) {
    try {
      // The card shelf can contain different types
      final title = cardShelf['title']?['runs']?[0]?['text'] as String?;
      if (title == null) return null;

      // Get thumbnail
      final thumbnails =
          cardShelf['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? thumbnails!.last['url'] as String?
          : null;

      // Get subtitle (artist/type info)
      final subtitleRuns = cardShelf['subtitle']?['runs'] as List?;
      final subtitle = subtitleRuns?.map((r) => r['text']).join() ?? '';

      // Get navigation endpoint to determine type
      final browseEndpoint =
          cardShelf['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint'];
      final watchEndpoint =
          cardShelf['title']?['runs']?[0]?['navigationEndpoint']?['watchEndpoint'];

      if (browseEndpoint != null) {
        final browseId = browseEndpoint['browseId'] as String?;
        if (browseId != null) {
          // Artist (UC prefix)
          if (browseId.startsWith('UC')) {
            return SearchResultItem.artist(
              Artist(id: browseId, name: title, thumbnailUrl: thumbnailUrl),
            );
          }
          // Album (MPREb prefix)
          if (browseId.startsWith('MPREb')) {
            return SearchResultItem.album(
              Album(
                id: browseId,
                title: title,
                artist: subtitle.replaceAll(RegExp(r'\s*•.*'), ''),
                thumbnailUrl: thumbnailUrl,
              ),
            );
          }
          // Playlist (VL or RDCLAK prefix)
          if (browseId.startsWith('VL') || browseId.startsWith('RDCLAK')) {
            return SearchResultItem.playlist(
              Playlist(
                id: browseId.startsWith('VL')
                    ? browseId.substring(2)
                    : browseId,
                title: title,
                thumbnailUrl: thumbnailUrl,
              ),
            );
          }
        }
      }

      // Track (watchEndpoint)
      if (watchEndpoint != null) {
        final videoId = watchEndpoint['videoId'] as String?;
        if (videoId != null) {
          return SearchResultItem.track(
            Track(
              id: videoId,
              title: title,
              artist: subtitle.replaceAll(RegExp(r'\s*•.*'), ''),
              duration: Duration.zero,
              thumbnailUrl: thumbnailUrl,
            ),
          );
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Playlist? _parsePlaylistDetails(
    Map<String, dynamic> response,
    String playlistId,
  ) {
    try {
      // Try multiple header locations (YouTube Music uses different structures)
      final header =
          response['header']?['musicDetailHeaderRenderer'] ??
          response['header']?['musicEditablePlaylistDetailHeaderRenderer']?['header']?['musicDetailHeaderRenderer'] ??
          response['header']?['musicResponsiveHeaderRenderer'];

      // Also try to get header from content tabs for some playlist types
      dynamic fallbackHeader;
      if (header == null) {
        fallbackHeader =
            _navigateJson(response, [
              'contents',
              'singleColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]) ??
            _navigateJson(response, [
              'contents',
              'twoColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]);
      }

      final activeHeader = header ?? fallbackHeader;

      // Debug logging
      if (activeHeader == null) {
        if (kDebugMode) {
          print('Playlist parse: No header found for $playlistId');
        }
        if (kDebugMode) {
          print('Playlist parse: Response keys: ${response.keys.toList()}');
        }
        if (response['header'] != null) {
          if (kDebugMode) {
            print(
              'Playlist parse: Header keys: ${(response['header'] as Map).keys.toList()}',
            );
          }
        }
      }

      // Parse title from various locations
      String title = 'Unknown Playlist';
      String? description;
      String? thumbnailUrl;
      String? author;

      if (activeHeader != null) {
        // Standard header parsing
        title =
            activeHeader['title']?['runs']?[0]?['text'] as String? ??
            (activeHeader['title']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join() ??
            'Unknown Playlist';

        description =
            activeHeader['description']?['runs']?[0]?['text'] as String? ??
            (activeHeader['description']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join();

        // Get thumbnail
        final thumbnails =
            activeHeader['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List? ??
            activeHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnailUrl = thumbnails.last['url'] as String?;
        }

        // Get author from subtitle
        final subtitleRuns =
            activeHeader['subtitle']?['runs'] as List? ??
            activeHeader['straplineTextOne']?['runs'] as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          author = subtitleRuns[0]['text'] as String?;
        }
      }

      if (title == 'Unknown Playlist') {
        final microformat = response['microformat']?['microformatDataRenderer'];
        if (microformat is Map) {
          final titleObj = microformat['title'];
          if (titleObj is Map) {
            title = titleObj['simpleText'] as String? ?? 'Unknown Playlist';
          } else if (titleObj is String) {
            title = titleObj;
          }

          if (thumbnailUrl == null) {
            final thumbObj = microformat['thumbnail'];
            if (thumbObj is Map) {
              final thumbs = thumbObj['thumbnails'] as List?;
              if (thumbs != null && thumbs.isNotEmpty) {
                thumbnailUrl = thumbs.last['url'];
              }
            }
          }
        }
      }

      // Parse tracks from multiple possible locations
      final tracks = <Track>[];

      // Try standard playlist shelf
      var contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
                'contents',
              ])
              as List?;

      // Try alternative structure (musicShelfRenderer)
      contents ??=
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
                0,
                'musicShelfRenderer',
                'contents',
              ])
              as List?;

      // Try two-column browse results (used for some playlists)
      contents ??=
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
                'contents',
              ])
              as List?;

      if (contents != null) {
        for (final item in contents) {
          final track = _parseTrackItem({
            'musicResponsiveListItemRenderer':
                item['musicResponsiveListItemRenderer'],
          });
          if (track != null) tracks.add(track);
        }
      }

      // If we got tracks but no header, still return the playlist
      if (tracks.isNotEmpty || activeHeader != null) {
        return Playlist(
          id: playlistId,
          title: title,
          description: description,
          thumbnailUrl: thumbnailUrl,
          author: author,
          trackCount: tracks.length,
          tracks: tracks,
          isYTMusic: true,
        );
      }

      if (kDebugMode) {
        print('Playlist parse: No content found for $playlistId');
      }
      return null;
    } catch (e, stack) {
      if (kDebugMode) {
        print('Error parsing playlist details: $e');
      }
      if (kDebugMode) {
        print('Stack: $stack');
      }
      return null;
    }
  }

  /// Parse playlist details with continuation token support
  (Playlist?, String?) _parsePlaylistDetailsWithContinuation(
    Map<String, dynamic> response,
    String playlistId,
  ) {
    try {
      // Try multiple header locations (YouTube Music uses different structures)
      final header =
          response['header']?['musicDetailHeaderRenderer'] ??
          response['header']?['musicEditablePlaylistDetailHeaderRenderer']?['header']?['musicDetailHeaderRenderer'] ??
          response['header']?['musicResponsiveHeaderRenderer'];

      // Also try to get header from content tabs for some playlist types
      dynamic fallbackHeader;
      if (header == null) {
        fallbackHeader =
            _navigateJson(response, [
              'contents',
              'singleColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]) ??
            _navigateJson(response, [
              'contents',
              'twoColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]);
      }

      final activeHeader = header ?? fallbackHeader;

      // Parse title from various locations
      String title = 'Unknown Playlist';
      String? description;
      String? thumbnailUrl;
      String? author;

      if (activeHeader != null) {
        title =
            activeHeader['title']?['runs']?[0]?['text'] as String? ??
            (activeHeader['title']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join() ??
            'Unknown Playlist';

        description =
            activeHeader['description']?['runs']?[0]?['text'] as String? ??
            (activeHeader['description']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join();

        final thumbnails =
            activeHeader['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List? ??
            activeHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnailUrl = thumbnails.last['url'] as String?;
        }

        final subtitleRuns =
            activeHeader['subtitle']?['runs'] as List? ??
            activeHeader['straplineTextOne']?['runs'] as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          author = subtitleRuns[0]['text'] as String?;
        }
      }

      if (title == 'Unknown Playlist') {
        final microformat = response['microformat']?['microformatDataRenderer'];
        if (microformat is Map) {
          final titleObj = microformat['title'];
          if (titleObj is Map) {
            title = titleObj['simpleText'] as String? ?? 'Unknown Playlist';
          } else if (titleObj is String) {
            title = titleObj;
          }

          if (thumbnailUrl == null) {
            final thumbObj = microformat['thumbnail'];
            if (thumbObj is Map) {
              final thumbs = thumbObj['thumbnails'] as List?;
              if (thumbs != null && thumbs.isNotEmpty) {
                thumbnailUrl = thumbs.last['url'];
              }
            }
          }
        }
      }

      // Parse tracks and get continuation
      final tracks = <Track>[];
      String? continuation;

      // Try two-column browse results first (most common for playlists like Liked Songs)
      var shelf =
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
              ])
              as Map?;

      var contents = shelf?['contents'] as List?;

      // Try singleColumn if twoColumn didn't work
      if (contents == null) {
        shelf =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicPlaylistShelfRenderer',
                ])
                as Map?;

        contents = shelf?['contents'] as List?;
      }

      // Try musicShelfRenderer
      if (contents == null) {
        shelf =
            _navigateJson(response, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                  0,
                  'musicShelfRenderer',
                ])
                as Map?;

        contents = shelf?['contents'] as List?;
      }

      // Get continuation from shelf
      if (shelf != null) {
        final continuations = shelf['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        }
      }

      if (contents != null) {
        for (final item in contents) {
          final track = _parseTrackItem({
            'musicResponsiveListItemRenderer':
                item['musicResponsiveListItemRenderer'],
          });
          if (track != null) tracks.add(track);
        }
      }

      if (tracks.isNotEmpty || activeHeader != null) {
        return (
          Playlist(
            id: playlistId,
            title: title,
            description: description,
            thumbnailUrl: thumbnailUrl,
            author: author,
            trackCount: tracks.length,
            tracks: tracks,
            isYTMusic: true,
          ),
          continuation,
        );
      }

      return (null, null);
    } catch (e, stack) {
      if (kDebugMode) {
        print('Error parsing playlist details with continuation: $e');
      }
      if (kDebugMode) {
        print('Stack: $stack');
      }
      return (null, null);
    }
  }

  /// Parse playlist continuation response
  (List<Track>, String?) _parsePlaylistContinuation(
    Map<String, dynamic> response,
  ) {
    final tracks = <Track>[];
    String? continuation;

    try {
      // Try musicPlaylistShelfContinuation
      var continuationContents =
          response['continuationContents']?['musicPlaylistShelfContinuation'];

      // Try musicShelfContinuation
      continuationContents ??=
          response['continuationContents']?['musicShelfContinuation'];

      if (continuationContents != null) {
        final contents = continuationContents['contents'] as List?;
        if (contents != null) {
          for (final item in contents) {
            final track = _parseTrackItem({
              'musicResponsiveListItemRenderer':
                  item['musicResponsiveListItemRenderer'],
            });
            if (track != null) tracks.add(track);
          }
        }

        // Get next continuation
        final continuations = continuationContents['continuations'] as List?;
        if (continuations != null && continuations.isNotEmpty) {
          continuation =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing playlist continuation: $e');
      }
    }

    return (tracks, continuation);
  }

  Album? _parseAlbumDetails(Map<String, dynamic> response, String albumId) {
    try {
      // Try multiple header locations
      final header =
          response['header']?['musicDetailHeaderRenderer'] ??
          response['header']?['musicResponsiveHeaderRenderer'];

      // Also try to get header from content tabs (common in two-column layouts)
      dynamic fallbackHeader;
      if (header == null) {
        fallbackHeader =
            _navigateJson(response, [
              'contents',
              'twoColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]) ??
            _navigateJson(response, [
              'contents',
              'singleColumnBrowseResultsRenderer',
              'tabs',
              0,
              'tabRenderer',
              'content',
              'sectionListRenderer',
              'contents',
              0,
              'musicResponsiveHeaderRenderer',
            ]);
      }

      final activeHeader = header ?? fallbackHeader;

      if (activeHeader == null) {
        if (kDebugMode) {
          print('Album parse: No header found for $albumId');
        }
        return null; // Can't parse without minimal info
      }

      // Parse title
      String title = 'Unknown Album';
      if (activeHeader['title'] != null) {
        title =
            activeHeader['title']?['runs']?[0]?['text'] as String? ??
            (activeHeader['title']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join() ??
            'Unknown Album';
      }

      // Parse subtitle (Artist, Year)
      final subtitleRuns =
          activeHeader['subtitle']?['runs'] as List? ??
          activeHeader['straplineTextOne']?['runs'] as List?;

      String artist = 'Unknown Artist';
      String? year;

      if (subtitleRuns != null) {
        for (final run in subtitleRuns) {
          final text = run['text'] as String?;
          if (text != null) {
            // Heuristic: If it has navigation, likely artist. If 4 digits, likely year.
            if (run['navigationEndpoint'] != null ||
                (text != '•' &&
                    !RegExp(r'^\d{4}$').hasMatch(text) &&
                    !text.contains('song'))) {
              // Assuming first non-year text is artist if not previously set or if has endpoint
              if (artist == 'Unknown Artist') artist = text;
            } else if (RegExp(r'^\d{4}$').hasMatch(text)) {
              year = text;
            }
          }
        }
      }

      // Get thumbnail
      final thumbnails =
          activeHeader['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List? ??
          activeHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;

      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      String? description;
      if (activeHeader['description'] != null) {
        description =
            activeHeader['description']?['runs']?[0]?['text'] as String? ??
            (activeHeader['description']?['runs'] as List?)
                ?.map((r) => r['text'])
                .join();
      }

      // Parse tracks
      final tracks = <Track>[];

      // Try standard album shelf
      var contents =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
                0,
                'musicShelfRenderer',
                'contents',
              ])
              as List?;

      // Try two-column browse results (Desktop Web often uses this for Albums)
      contents ??=
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicShelfRenderer',
                'contents',
              ])
              as List?;

      // Sometimes it's a playlist shelf for albums?
      contents ??=
          _navigateJson(response, [
                'contents',
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer',
                'contents',
                0,
                'musicPlaylistShelfRenderer',
                'contents',
              ])
              as List?;

      if (contents != null) {
        for (final item in contents) {
          final track = _parseTrackItem(item);
          if (track != null) tracks.add(track);
        }
      }

      return Album(
        id: albumId,
        title: title,
        artist: artist,
        year: year,
        thumbnailUrl: thumbnailUrl,
        description: description,
        tracks: tracks,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing album details: $e');
      }
      return null;
    }
  }

  Artist? _parseArtistDetails(Map<String, dynamic> response, String channelId) {
    try {
      final header =
          response['header']?['musicImmersiveHeaderRenderer'] ??
          response['header']?['musicVisualHeaderRenderer'] ??
          response['header']?['musicResponsiveHeaderRenderer'];

      String? name;
      String? thumbnailUrl;
      String? description;
      int? subscriberCount;

      if (header != null) {
        name = header['title']?['runs']?[0]?['text'] as String?;

        final thumbnails =
            header['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnailUrl = thumbnails.last['url'] as String?;
        }

        description = header['description']?['runs']?[0]?['text'] as String?;

        final subText =
            header['subscriptionButton']?['subscribeButtonRenderer']?['subscriberCountText']?['runs']?[0]?['text']
                as String?;
        if (subText != null) {
          // "1.2M subscribers" -> parse number?
          // Simple parsing: remove non-digits (handle K/M)
          // For now just keep string if model allows? Model expects int.
          // Regex to find number.
          // "3.75M subscribers"
          // "12K subscribers"
          // "100 subscribers"
          // I'll skip complex parsing for now or do a quick one
          if (subText.contains('K')) {
            subscriberCount =
                (double.parse(subText.replaceAll(RegExp(r'[^0-9.]'), '')) *
                        1000)
                    .toInt();
          } else if (subText.contains('M')) {
            subscriberCount =
                (double.parse(subText.replaceAll(RegExp(r'[^0-9.]'), '')) *
                        1000000)
                    .toInt();
          } else {
            subscriberCount = int.tryParse(
              subText.replaceAll(RegExp(r'[^0-9]'), ''),
            );
          }
        }
      }

      // Microformat fallback for name/thumb
      if (name == null) {
        final microformat = response['microformat']?['microformatDataRenderer'];
        name = microformat?['title'] as String? ?? 'Unknown Artist';
        if (thumbnailUrl == null) {
          final thumbs = microformat?['thumbnail']?['thumbnails'] as List?;
          if (thumbs != null && thumbs.isNotEmpty) {
            thumbnailUrl = thumbs.last['url'];
          }
        }
      }

      final topTracks = <Track>[];
      final albums = <Album>[];
      final singles = <Album>[];
      final appearsOn = <Album>[];
      final playlists = <Playlist>[];
      final similarArtists = <Artist>[];
      String? songsBrowseId;
      String? songsParams;

      // Parse Content Sections
      final sections =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0, // Usually first tab is "Home" or "Songs"
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (sections != null) {
        for (final section in sections) {
          // Top Songs (MusicShelf)
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            final title = musicShelf['title']?['runs']?[0]?['text'] as String?;
            if (title == 'Songs' || title == 'Top songs') {
              // Extract "See all" browse ID and params for songs
              final moreButton =
                  musicShelf['bottomEndpoint']?['browseEndpoint'];
              if (moreButton != null) {
                songsBrowseId = moreButton['browseId'] as String?;
                songsParams = moreButton['params'] as String?;
              }

              final contents = musicShelf['contents'] as List?;
              if (contents != null) {
                for (final item in contents) {
                  final track = _parseTrackItem(item);
                  if (track != null) topTracks.add(track);
                }
              }
            }
          }

          // Albums / Singles / EPs / Appears On (MusicCarouselShelf)
          final musicCarousel = section['musicCarouselShelfRenderer'];
          if (musicCarousel != null) {
            final title =
                musicCarousel['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text']
                    as String?;

            final contents = musicCarousel['contents'] as List?;
            if (contents == null) continue;

            // Parse album items from carousel
            final parsedAlbums = <Album>[];
            for (final item in contents) {
              final r = item['musicTwoRowItemRenderer'];
              if (r != null) {
                final id =
                    r['navigationEndpoint']?['browseEndpoint']?['browseId'];
                if (id != null) {
                  final albumTitle =
                      r['title']?['runs']?[0]?['text'] ?? 'Unknown Album';
                  final thumb =
                      r['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                          ?.last['url'];
                  // Subtitle may contain "Album • 2023" or "Single • 2023"
                  final subtitleRuns = r['subtitle']?['runs'] as List?;
                  String? year;
                  if (subtitleRuns != null) {
                    // Usually: "[type] • [year]" or "[artist] • [year]"
                    final subtitleText = subtitleRuns
                        .map((r) => r['text'])
                        .join();
                    // Extract year (4 digits)
                    final yearMatch = RegExp(
                      r'\b(19|20)\d{2}\b',
                    ).firstMatch(subtitleText);
                    if (yearMatch != null) {
                      year = yearMatch.group(0);
                    }
                  }

                  parsedAlbums.add(
                    Album(
                      id: id,
                      title: albumTitle,
                      artist: name,
                      thumbnailUrl: thumb,
                      year: year,
                    ),
                  );
                }
              }
            }

            // Categorize by shelf title
            final lowerTitle = title?.toLowerCase() ?? '';
            if (lowerTitle.contains('albums')) {
              albums.addAll(parsedAlbums);
            } else if (lowerTitle.contains('singles') ||
                lowerTitle.contains('eps')) {
              singles.addAll(parsedAlbums);
            } else if (lowerTitle.contains('appears on') ||
                lowerTitle.contains('featured on')) {
              appearsOn.addAll(parsedAlbums);
            }
          }

          // Playlists shelf
          final playlistShelf = section['musicCarouselShelfRenderer'];
          if (playlistShelf != null) {
            final title =
                playlistShelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text']
                    as String?;
            final lowerTitle = title?.toLowerCase() ?? '';

            if (lowerTitle.contains('playlist') ||
                lowerTitle.contains('featuring')) {
              final contents = playlistShelf['contents'] as List?;
              if (contents != null) {
                for (final item in contents) {
                  final r = item['musicTwoRowItemRenderer'];
                  if (r != null) {
                    final id =
                        r['navigationEndpoint']?['browseEndpoint']?['browseId'];
                    if (id != null && (id as String).startsWith('VL')) {
                      final playlistTitle =
                          r['title']?['runs']?[0]?['text'] ?? 'Playlist';
                      final thumb =
                          r['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                              ?.last['url'];
                      final author = r['subtitle']?['runs']?[0]?['text'];

                      playlists.add(
                        Playlist(
                          id: id.replaceFirst('VL', ''),
                          title: playlistTitle,
                          thumbnailUrl: thumb,
                          author: author,
                        ),
                      );
                    }
                  }
                }
              }
            }

            // Similar artists / Fans also like
            if (lowerTitle.contains('fans also like') ||
                lowerTitle.contains('similar artists') ||
                lowerTitle.contains('related artists')) {
              final contents = playlistShelf['contents'] as List?;
              if (contents != null) {
                for (final item in contents) {
                  final r = item['musicTwoRowItemRenderer'];
                  if (r != null) {
                    final id =
                        r['navigationEndpoint']?['browseEndpoint']?['browseId'];
                    if (id != null && (id as String).startsWith('UC')) {
                      final artistName =
                          r['title']?['runs']?[0]?['text'] ?? 'Artist';
                      final thumb =
                          r['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                              ?.last['url'];

                      similarArtists.add(
                        Artist(id: id, name: artistName, thumbnailUrl: thumb),
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }

      return Artist(
        id: channelId,
        name: name,
        thumbnailUrl: thumbnailUrl,
        description: description,
        subscriberCount: subscriberCount,
        topTracks: topTracks,
        albums: albums,
        singles: singles.isNotEmpty ? singles : null,
        appearsOn: appearsOn.isNotEmpty ? appearsOn : null,
        playlists: playlists.isNotEmpty ? playlists : null,
        similarArtists: similarArtists.isNotEmpty ? similarArtists : null,
        songsBrowseId: songsBrowseId,
        songsParams: songsParams,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing artist details: $e');
      }
      return null;
    }
  }

  // Helper to navigate nested JSON
  dynamic _navigateJson(Map<String, dynamic> json, List<dynamic> path) {
    dynamic current = json;
    for (final key in path) {
      if (current == null) return null;
      if (key is int) {
        if (current is List && key < current.length) {
          current = current[key];
        } else {
          return null;
        }
      } else {
        if (current is Map) {
          current = current[key];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  Duration _parseDuration(String text) {
    final parts = text.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 2) {
      return Duration(minutes: parts[0], seconds: parts[1]);
    } else if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration.zero;
  }

  // ============ HOME PAGE PARSER ============

  HomePageContent _parseHomePageContent(Map<String, dynamic> response) {
    final shelves = <HomeShelf>[];

    try {
      // Navigate to the contents
      final tabs =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
              ])
              as List?;

      if (tabs == null || tabs.isEmpty) return HomePageContent.empty;

      final sectionList =
          _navigateJson(tabs[0], [
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'contents',
              ])
              as List?;

      if (sectionList == null) return HomePageContent.empty;

      int shelfIndex = 0;
      for (final section in sectionList) {
        final shelf = _parseHomeShelf(section, shelfIndex);
        if (shelf != null && shelf.items.isNotEmpty) {
          shelves.add(shelf);
          shelfIndex++;
        }
      }

      // Get continuation token if available
      final continuations =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
                0,
                'tabRenderer',
                'content',
                'sectionListRenderer',
                'continuations',
              ])
              as List?;

      String? continuationToken;
      if (continuations != null && continuations.isNotEmpty) {
        continuationToken =
            continuations[0]['nextContinuationData']?['continuation']
                as String?;
      }

      return HomePageContent(
        shelves: shelves,
        continuationToken: continuationToken,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing home page: $e');
      }
      return HomePageContent.empty;
    }
  }

  HomeShelf? _parseHomeShelf(Map<String, dynamic> section, int index) {
    try {
      // Try different renderer types
      final musicCarouselShelfRenderer = section['musicCarouselShelfRenderer'];
      final musicShelfRenderer = section['musicShelfRenderer'];
      final musicImmersiveCarouselShelfRenderer =
          section['musicImmersiveCarouselShelfRenderer'];
      final musicTastebuilderShelfRenderer =
          section['musicTastebuilderShelfRenderer'];
      final gridRenderer = section['gridRenderer'];

      if (musicCarouselShelfRenderer != null) {
        return _parseMusicCarouselShelf(musicCarouselShelfRenderer, index);
      } else if (musicTastebuilderShelfRenderer != null) {
        return _parseTastebuilderShelf(musicTastebuilderShelfRenderer, index);
      } else if (musicShelfRenderer != null) {
        return _parseMusicShelfRenderer(musicShelfRenderer, index);
      } else if (musicImmersiveCarouselShelfRenderer != null) {
        return _parseImmersiveCarouselShelf(
          musicImmersiveCarouselShelfRenderer,
          index,
        );
      } else if (gridRenderer != null) {
        return _parseGridShelf(gridRenderer, index);
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing shelf: $e');
      }
      return null;
    }
  }

  HomeShelf? _parseMusicCarouselShelf(
    Map<String, dynamic> renderer,
    int index,
  ) {
    final header = renderer['header']?['musicCarouselShelfBasicHeaderRenderer'];
    if (header == null) return null;

    // Get title
    final titleRuns = header['title']?['runs'] as List?;
    final title = titleRuns?.map((r) => r['text']).join() ?? 'Recommendations';

    // Get strapline (small text above title)
    final straplineRuns = header['strapline']?['runs'] as List?;
    final strapline = straplineRuns?.map((r) => r['text']).join();

    // Get browse endpoint for "See all"
    final browseEndpoint =
        header['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint'];
    final browseId = browseEndpoint?['browseId'] as String?;

    // Determine shelf type from title
    final shelfType = _determineShelfType(title, strapline);

    // Parse items
    final contents = renderer['contents'] as List? ?? [];
    final items = <HomeShelfItem>[];

    for (final content in contents) {
      final item = _parseCarouselItem(content, shelfType);
      if (item != null) items.add(item);
    }

    return HomeShelf(
      id: 'shelf_$index',
      title: title,
      strapline: strapline,
      type: shelfType,
      items: items,
      browseId: browseId,
    );
  }

  HomeShelf? _parseMusicShelfRenderer(
    Map<String, dynamic> renderer,
    int index,
  ) {
    final titleRuns = renderer['title']?['runs'] as List?;
    final title = titleRuns?.map((r) => r['text']).join() ?? 'Recommendations';

    final shelfType = _determineShelfType(title, null);

    final contents = renderer['contents'] as List? ?? [];
    final items = <HomeShelfItem>[];

    for (final content in contents) {
      final item = _parseMusicShelfItem(content, shelfType);
      if (item != null) items.add(item);
    }

    // Get playlistId if this is a playable shelf (like Quick Picks)
    final playButton = renderer['playAllButton'];
    String? playlistId;
    if (playButton != null) {
      playlistId =
          playButton['buttonRenderer']?['navigationEndpoint']?['watchEndpoint']?['playlistId']
              as String?;
    }

    return HomeShelf(
      id: 'shelf_$index',
      title: title,
      type: shelfType,
      items: items,
      isPlayable: playlistId != null,
      playlistId: playlistId,
    );
  }

  HomeShelf? _parseImmersiveCarouselShelf(
    Map<String, dynamic> renderer,
    int index,
  ) {
    final header =
        renderer['header']?['musicImmersiveCarouselShelfBasicHeaderRenderer'];
    final titleRuns = header?['title']?['runs'] as List?;
    final title = titleRuns?.map((r) => r['text']).join() ?? 'Featured';

    final contents = renderer['contents'] as List? ?? [];
    final items = <HomeShelfItem>[];

    for (final content in contents) {
      final item = _parseCarouselItem(content, HomeShelfType.mixedForYou);
      if (item != null) items.add(item);
    }

    return HomeShelf(
      id: 'shelf_$index',
      title: title,
      type: HomeShelfType.mixedForYou,
      items: items,
    );
  }

  /// Parse Taste Builder shelves (personalized: Mixed For You, Listen Again, etc.)
  HomeShelf? _parseTastebuilderShelf(Map<String, dynamic> renderer, int index) {
    try {
      final header = renderer['header']?['musicResponsiveHeaderRenderer'];
      if (header == null) return null;

      final titleRuns = header['title']?['runs'] as List?;
      final title = titleRuns?.map((r) => r['text']).join() ?? 'Personalized';

      final subtitleRuns = header['subtitle']?['runs'] as List?;
      final strapline = subtitleRuns?.map((r) => r['text']).join();

      // Determine type from title
      HomeShelfType shelfType = HomeShelfType.unknown;
      if (title.contains('Mixed') || title.contains('Mix')) {
        shelfType = HomeShelfType.mixedForYou;
      } else if (title.contains('Listen') || title.contains('Again')) {
        shelfType = HomeShelfType.listenAgain;
      } else if (title.contains('Discover')) {
        shelfType = HomeShelfType.mixedForYou;
      } else if (title.contains('Forgotten')) {
        shelfType = HomeShelfType.forgottenFavorites;
      }

      // Parse contents
      final contents = renderer['contents'] as List? ?? [];
      final items = <HomeShelfItem>[];

      for (final content in contents) {
        final item = _parseCarouselItem(content, shelfType);
        if (item != null) items.add(item);
      }

      if (items.isEmpty) return null;

      return HomeShelf(
        id: 'shelf_$index',
        title: title,
        strapline: strapline,
        type: shelfType,
        items: items,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing tastebuilder shelf: $e');
      }
      return null;
    }
  }

  HomeShelf? _parseGridShelf(Map<String, dynamic> renderer, int index) {
    final header = renderer['header']?['gridHeaderRenderer'];
    final title = header?['title']?['runs']?[0]?['text'] as String? ?? 'More';

    final items = renderer['items'] as List? ?? [];
    final parsedItems = <HomeShelfItem>[];

    for (final item in items) {
      final parsed = _parseGridItem(item);
      if (parsed != null) parsedItems.add(parsed);
    }

    return HomeShelf(
      id: 'shelf_$index',
      title: title,
      type: HomeShelfType.unknown,
      items: parsedItems,
    );
  }

  HomeShelfType _determineShelfType(String title, String? strapline) {
    final lowerTitle = title.toLowerCase();
    final lowerStrapline = strapline?.toLowerCase() ?? '';

    // Quick picks
    if (lowerTitle.contains('quick picks') ||
        lowerTitle.contains('start radio')) {
      return HomeShelfType.quickPicks;
    }

    // Mixed for you / personalized mixes
    if (lowerTitle.contains('mixed for you') ||
        lowerTitle.contains('your mixes') ||
        lowerTitle.contains('supermix') ||
        lowerTitle.contains('my mix') ||
        lowerStrapline.contains('based on your listening')) {
      return HomeShelfType.mixedForYou;
    }

    // Discover mix
    if (lowerTitle.contains('discover mix') ||
        lowerTitle.contains('discover weekly') ||
        lowerTitle.contains('discovery')) {
      return HomeShelfType.discoverMix;
    }

    // New release mix
    if (lowerTitle.contains('new release') && lowerTitle.contains('mix')) {
      return HomeShelfType.newReleaseMix;
    }

    // Similar to artist
    if (lowerTitle.contains('similar to') ||
        lowerTitle.contains('fans also like') ||
        lowerTitle.contains('you might also like')) {
      return HomeShelfType.similarToArtist;
    }

    // New releases (albums)
    if (lowerTitle.contains('new release') ||
        lowerTitle.contains('new album') ||
        lowerTitle.contains('fresh')) {
      return HomeShelfType.newReleases;
    }

    // Forgotten favorites
    if (lowerTitle.contains('forgotten') ||
        lowerTitle.contains('throwback') ||
        lowerTitle.contains('revisit') ||
        lowerTitle.contains('blast from')) {
      return HomeShelfType.forgottenFavorites;
    }

    // Listen again / Recently played
    if (lowerTitle.contains('listen again') ||
        lowerTitle.contains('recently played') ||
        lowerTitle.contains('play again')) {
      return HomeShelfType.listenAgain;
    }

    // Charts
    if (lowerTitle.contains('chart') ||
        lowerTitle.contains('top 100') ||
        lowerTitle.contains('top songs') ||
        lowerTitle.contains('trending')) {
      return HomeShelfType.charts;
    }

    // Trending
    if (lowerTitle.contains('trending')) {
      return HomeShelfType.trending;
    }

    // Moods
    if (lowerTitle.contains('mood') ||
        lowerTitle.contains('feel good') ||
        lowerTitle.contains('chill') ||
        lowerTitle.contains('workout') ||
        lowerTitle.contains('focus') ||
        lowerTitle.contains('sleep') ||
        lowerTitle.contains('romance')) {
      return HomeShelfType.moods;
    }

    // Genres
    if (lowerTitle.contains('genre') ||
        lowerTitle.contains('pop') ||
        lowerTitle.contains('rock') ||
        lowerTitle.contains('hip hop') ||
        lowerTitle.contains('r&b') ||
        lowerTitle.contains('electronic') ||
        lowerTitle.contains('country')) {
      return HomeShelfType.genres;
    }

    // Videos
    if (lowerTitle.contains('video') || lowerTitle.contains('music video')) {
      return HomeShelfType.videos;
    }

    // Podcasts
    if (lowerTitle.contains('podcast') ||
        lowerTitle.contains('long listening')) {
      return HomeShelfType.podcasts;
    }

    // Artists
    if (lowerTitle.contains('artist') ||
        lowerTitle.contains('recommended artist')) {
      return HomeShelfType.artists;
    }

    return HomeShelfType.unknown;
  }

  HomeShelfItem? _parseCarouselItem(
    Map<String, dynamic> content,
    HomeShelfType shelfType,
  ) {
    try {
      // Try musicTwoRowItemRenderer (most common for playlists/albums)
      final twoRowRenderer = content['musicTwoRowItemRenderer'];
      if (twoRowRenderer != null) {
        return _parseTwoRowItem(twoRowRenderer, shelfType);
      }

      // Try musicResponsiveListItemRenderer (for tracks)
      final responsiveRenderer = content['musicResponsiveListItemRenderer'];
      if (responsiveRenderer != null) {
        return _parseResponsiveListItem(responsiveRenderer);
      }

      // Try musicNavigationButtonRenderer (for mood/genre pills)
      final navButtonRenderer = content['musicNavigationButtonRenderer'];
      if (navButtonRenderer != null) {
        return _parseNavigationButton(navButtonRenderer);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  HomeShelfItem? _parseTwoRowItem(
    Map<String, dynamic> renderer,
    HomeShelfType shelfType,
  ) {
    try {
      // Get title
      final title =
          renderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown';

      // Get subtitle
      final subtitleRuns = renderer['subtitle']?['runs'] as List?;
      final subtitle = subtitleRuns?.map((r) => r['text']).join() ?? '';

      // Get thumbnail
      final thumbnails =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      // Get navigation endpoint
      final navEndpoint = renderer['navigationEndpoint'];
      final browseEndpoint = navEndpoint?['browseEndpoint'];
      final watchEndpoint = navEndpoint?['watchEndpoint'];

      String? navigationId;
      String? playlistId;
      String? videoId;
      HomeShelfItemType itemType = HomeShelfItemType.unknown;

      if (browseEndpoint != null) {
        navigationId = browseEndpoint['browseId'] as String?;
        final pageType =
            browseEndpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
                as String?;

        if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
          itemType = HomeShelfItemType.album;
        } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
          itemType = shelfType == HomeShelfType.mixedForYou
              ? HomeShelfItemType.mix
              : HomeShelfItemType.playlist;
          // Extract playlist ID from browse ID
          if (navigationId != null && navigationId.startsWith('VL')) {
            playlistId = navigationId.substring(2);
          } else {
            playlistId = navigationId;
          }
        } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
          itemType = HomeShelfItemType.artist;
        }
      } else if (watchEndpoint != null) {
        videoId = watchEndpoint['videoId'] as String?;
        playlistId = watchEndpoint['playlistId'] as String?;
        navigationId = videoId;
        itemType = HomeShelfItemType.song;
      }

      // Check aspect ratio for mix detection
      final aspectRatio =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnailCrop']
              as String?;
      if (aspectRatio == 'MUSIC_THUMBNAIL_CROP_CIRCLE') {
        itemType = HomeShelfItemType.artist;
      }

      return HomeShelfItem(
        id: navigationId ?? title.hashCode.toString(),
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        navigationId: navigationId,
        itemType: itemType,
        playlistId: playlistId,
        videoId: videoId,
      );
    } catch (e) {
      return null;
    }
  }

  HomeShelfItem? _parseResponsiveListItem(Map<String, dynamic> renderer) {
    try {
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Get title
      final titleRuns =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
              as List?;
      final title = titleRuns?.map((r) => r['text']).join() ?? 'Unknown';

      // Get artist and artistId
      String? artist;
      String? artistId;
      if (flexColumns.length > 1) {
        final artistRuns =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (artistRuns != null) {
          // Build artist string and extract first artist's browseId
          final artistParts = <String>[];
          for (final run in artistRuns) {
            final text = run['text'] as String?;
            if (text != null) artistParts.add(text);
            // Extract artistId from first artist with browse endpoint
            if (artistId == null) {
              final browseEndpoint =
                  run['navigationEndpoint']?['browseEndpoint'];
              if (browseEndpoint != null) {
                final browseId = browseEndpoint['browseId'] as String?;
                // Artist IDs start with 'UC'
                if (browseId != null && browseId.startsWith('UC')) {
                  artistId = browseId;
                }
              }
            }
          }
          artist = artistParts.join();
        }
      }

      // Get thumbnail
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      String? thumbnailUrl;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnailUrl = thumbnails.last['url'] as String?;
      }

      // Get video ID
      final overlay = renderer['overlay']?['musicItemThumbnailOverlayRenderer'];
      final playEndpoint =
          overlay?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
      final videoId = playEndpoint?['watchEndpoint']?['videoId'] as String?;

      if (videoId == null) return null;

      return HomeShelfItem(
        id: videoId,
        title: title,
        subtitle: artist,
        thumbnailUrl: thumbnailUrl,
        itemType: HomeShelfItemType.song,
        videoId: videoId,
        artistId: artistId,
      );
    } catch (e) {
      return null;
    }
  }

  HomeShelfItem? _parseMusicShelfItem(
    Map<String, dynamic> content,
    HomeShelfType shelfType,
  ) {
    // Music shelf items are typically tracks
    return _parseCarouselItem(content, shelfType);
  }

  HomeShelfItem? _parseNavigationButton(Map<String, dynamic> renderer) {
    try {
      final buttonText =
          renderer['buttonText']?['runs']?[0]?['text'] as String?;
      if (buttonText == null) return null;

      final browseEndpoint = renderer['clickCommand']?['browseEndpoint'];
      final browseId = browseEndpoint?['browseId'] as String?;

      // These are typically mood/genre pills
      final solid = renderer['solid'];
      String? thumbnailUrl;
      if (solid != null) {
        // Has a colored background
      }

      return HomeShelfItem(
        id: browseId ?? buttonText.hashCode.toString(),
        title: buttonText,
        navigationId: browseId,
        itemType: HomeShelfItemType.mood,
      );
    } catch (e) {
      return null;
    }
  }

  HomeShelfItem? _parseGridItem(Map<String, dynamic> item) {
    final renderer = item['musicTwoRowItemRenderer'];
    if (renderer != null) {
      return _parseTwoRowItem(renderer, HomeShelfType.unknown);
    }
    return null;
  }

  /// Parse continuation response for home page
  HomePageContent _parseHomePageContinuation(Map<String, dynamic> response) {
    final shelves = <HomeShelf>[];

    try {
      // Continuation responses have a different structure
      final continuationContents = response['continuationContents'];
      if (continuationContents == null) return HomePageContent.empty;

      final sectionListContinuation =
          continuationContents['sectionListContinuation'];
      if (sectionListContinuation == null) return HomePageContent.empty;

      final contents = sectionListContinuation['contents'] as List?;
      if (contents == null) return HomePageContent.empty;

      int shelfIndex = 100; // Start from 100 to avoid ID conflicts
      for (final section in contents) {
        final shelf = _parseHomeShelf(section, shelfIndex);
        if (shelf != null && shelf.items.isNotEmpty) {
          shelves.add(shelf);
          shelfIndex++;
        }
      }

      // Get next continuation token
      final continuations = sectionListContinuation['continuations'] as List?;
      String? continuationToken;
      if (continuations != null && continuations.isNotEmpty) {
        continuationToken =
            continuations[0]['nextContinuationData']?['continuation']
                as String?;
      }

      if (kDebugMode) {
        print(
          'Continuation parsed: ${shelves.length} new shelves, hasMore=${continuationToken != null}',
        );
      }

      return HomePageContent(
        shelves: shelves,
        continuationToken: continuationToken,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing home page continuation: $e');
      }
      return HomePageContent.empty;
    }
  }

  /// Parse browse shelf result (for "More" / "See all" pages)
  BrowseShelfResult _parseBrowseShelfResult(
    Map<String, dynamic> response,
    String browseId,
  ) {
    final items = <HomeShelfItem>[];
    String? continuationToken;
    String? title;

    try {
      // Try to get title from header
      final header = response['header'];
      if (header != null) {
        title =
            header['musicHeaderRenderer']?['title']?['runs']?[0]?['text']
                as String?;
        title ??=
            header['musicDetailHeaderRenderer']?['title']?['runs']?[0]?['text']
                as String?;
      }

      // Navigate to contents - different paths for different browse types
      final tabs =
          _navigateJson(response, [
                'contents',
                'singleColumnBrowseResultsRenderer',
                'tabs',
              ])
              as List?;

      List? contents;

      if (kDebugMode) {
        print(
          'BrowseShelf Parse: tabs=${tabs != null}, tabsLength=${tabs?.length ?? 0}',
        );
      }

      if (tabs != null && tabs.isNotEmpty) {
        // Standard tab structure
        contents =
            _navigateJson(tabs[0], [
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                ])
                as List?;

        if (kDebugMode) {
          print(
            'BrowseShelf Parse: sectionListContents=${contents?.length ?? 0}',
          );
        }

        // Get continuation from sectionListRenderer
        final continuations =
            _navigateJson(tabs[0], [
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'continuations',
                ])
                as List?;

        if (continuations != null && continuations.isNotEmpty) {
          continuationToken =
              continuations[0]['nextContinuationData']?['continuation']
                  as String?;
        }
      }

      // Try alternative path for grid results
      if (contents == null) {
        contents =
            _navigateJson(response, [
                  'contents',
                  'twoColumnBrowseResultsRenderer',
                  'tabs',
                  0,
                  'tabRenderer',
                  'content',
                  'sectionListRenderer',
                  'contents',
                ])
                as List?;
      }

      // Parse continuation response
      if (contents == null) {
        final continuationContents = response['continuationContents'];
        if (continuationContents != null) {
          final gridContinuation = continuationContents['gridContinuation'];
          final musicShelfContinuation =
              continuationContents['musicShelfContinuation'];
          final musicPlaylistShelfContinuation =
              continuationContents['musicPlaylistShelfContinuation'];
          final sectionListContinuation =
              continuationContents['sectionListContinuation'];

          if (gridContinuation != null) {
            contents = gridContinuation['items'] as List?;
            final conts = gridContinuation['continuations'] as List?;
            if (conts != null && conts.isNotEmpty) {
              continuationToken =
                  conts[0]['nextContinuationData']?['continuation'] as String?;
            }
          } else if (musicPlaylistShelfContinuation != null) {
            // Artist songs continuation uses musicPlaylistShelfContinuation
            contents = musicPlaylistShelfContinuation['contents'] as List?;
            final conts =
                musicPlaylistShelfContinuation['continuations'] as List?;
            if (conts != null && conts.isNotEmpty) {
              continuationToken =
                  conts[0]['nextContinuationData']?['continuation'] as String?;
            }
          } else if (musicShelfContinuation != null) {
            contents = musicShelfContinuation['contents'] as List?;
            final conts = musicShelfContinuation['continuations'] as List?;
            if (conts != null && conts.isNotEmpty) {
              continuationToken =
                  conts[0]['nextContinuationData']?['continuation'] as String?;
            }
          } else if (sectionListContinuation != null) {
            contents = sectionListContinuation['contents'] as List?;
            final conts = sectionListContinuation['continuations'] as List?;
            if (conts != null && conts.isNotEmpty) {
              continuationToken =
                  conts[0]['nextContinuationData']?['continuation'] as String?;
            }
          }
        }
      }

      if (contents != null) {
        if (kDebugMode) {
          print(
            'BrowseShelf Parse: Processing ${contents.length} content items',
          );
        }
        for (final content in contents) {
          // Log what renderers are in this content
          final keys = (content as Map<String, dynamic>).keys.toList();
          if (kDebugMode) {
            print('BrowseShelf Parse: Content keys: $keys');
          }

          // Try to parse as different item types
          final item = _parseBrowseItem(content);
          if (item != null) {
            items.add(item);
          }

          // Handle musicPlaylistShelfRenderer - used by artist songs
          final playlistShelfContents =
              content['musicPlaylistShelfRenderer']?['contents'] as List?;
          if (playlistShelfContents != null) {
            if (kDebugMode) {
              print(
                'BrowseShelf Parse: Found musicPlaylistShelfRenderer with ${playlistShelfContents.length} items',
              );
            }
            // Get continuation from musicPlaylistShelfRenderer
            final playlistContinuations =
                content['musicPlaylistShelfRenderer']?['continuations']
                    as List?;
            if (playlistContinuations != null &&
                playlistContinuations.isNotEmpty) {
              continuationToken =
                  playlistContinuations[0]['nextContinuationData']?['continuation']
                      as String?;
              if (kDebugMode) {
                print(
                  'BrowseShelf Parse: Found continuation token: ${continuationToken != null}',
                );
              }
            }

            for (final shelfItem in playlistShelfContents) {
              final parsedItem = _parseBrowseItem(shelfItem);
              if (parsedItem != null) {
                items.add(parsedItem);
              }
            }
          }

          // Also check for nested items in shelf renderers
          final shelfContents =
              content['musicShelfRenderer']?['contents'] as List?;
          if (shelfContents != null) {
            for (final shelfItem in shelfContents) {
              final parsedItem = _parseBrowseItem(shelfItem);
              if (parsedItem != null) {
                items.add(parsedItem);
              }
            }
          }

          // Check for carousel items
          final carouselContents =
              content['musicCarouselShelfRenderer']?['contents'] as List?;
          if (carouselContents != null) {
            for (final carouselItem in carouselContents) {
              final parsedItem = _parseBrowseItem(carouselItem);
              if (parsedItem != null) {
                items.add(parsedItem);
              }
            }
          }

          // Check for grid items
          final gridItems = content['gridRenderer']?['items'] as List?;
          if (gridItems != null) {
            for (final gridItem in gridItems) {
              final parsedItem = _parseBrowseItem(gridItem);
              if (parsedItem != null) {
                items.add(parsedItem);
              }
            }
          }
        }
      }

      if (kDebugMode) {
        print(
          'BrowseShelf: Parsed ${items.length} items, hasMore=${continuationToken != null}',
        );
      }

      return BrowseShelfResult(
        items: items,
        continuationToken: continuationToken,
        title: title,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing browse shelf result: $e');
      }
      return BrowseShelfResult(items: items, continuationToken: null);
    }
  }

  /// Parse a single item from browse results
  HomeShelfItem? _parseBrowseItem(Map<String, dynamic> item) {
    try {
      // musicTwoRowItemRenderer - albums, playlists, artists
      final twoRowRenderer = item['musicTwoRowItemRenderer'];
      if (twoRowRenderer != null) {
        final title = twoRowRenderer['title']?['runs']?[0]?['text'] as String?;
        final subtitle = (twoRowRenderer['subtitle']?['runs'] as List?)
            ?.map((r) => r['text'])
            .join('');
        final thumbnail =
            twoRowRenderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                    ?.last['url']
                as String?;

        final navEndpoint = twoRowRenderer['navigationEndpoint'];
        final browseEndpoint = navEndpoint?['browseEndpoint'];
        final watchEndpoint = navEndpoint?['watchEndpoint'];

        final browseId = browseEndpoint?['browseId'] as String?;
        final videoId = watchEndpoint?['videoId'] as String?;
        final pageType =
            browseEndpoint?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
                as String?;

        HomeShelfItemType itemType = HomeShelfItemType.unknown;
        if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
          itemType = HomeShelfItemType.album;
        } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
          itemType = HomeShelfItemType.playlist;
        } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
          itemType = HomeShelfItemType.artist;
        } else if (videoId != null) {
          itemType = HomeShelfItemType.song;
        }

        if (title != null) {
          return HomeShelfItem(
            id: browseId ?? videoId ?? title,
            title: title,
            subtitle: subtitle,
            thumbnailUrl: thumbnail,
            navigationId: browseId,
            videoId: videoId,
            itemType: itemType,
          );
        }
      }

      // musicResponsiveListItemRenderer - songs in lists
      final responsiveRenderer = item['musicResponsiveListItemRenderer'];
      if (responsiveRenderer != null) {
        final track = _parseTrackItem(item);
        if (track != null) {
          return HomeShelfItem(
            id: track.id,
            title: track.title,
            subtitle: track.artist,
            thumbnailUrl: track.thumbnailUrl,
            videoId: track.id,
            itemType: HomeShelfItemType.song,
            artistId: track.artistId.isNotEmpty ? track.artistId : null,
          );
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}

/// Top-level function for compute() - decodes JSON in background isolate
/// Must be top-level to work with compute()
Map<String, dynamic> _jsonDecodeIsolate(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
