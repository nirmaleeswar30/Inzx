import 'package:flutter/foundation.dart' show kDebugMode, compute;
import '../models/models.dart';
import 'ytmusic_api_service.dart';

/// Search filter types matching YouTube Music's categories
enum SearchFilter { all, songs, albums, artists, playlists, videos }

/// Represents a "top result" from YouTube Music search
/// This is YouTube's best guess at what the user is looking for
class TopResult {
  final SearchResultType type;
  final Track? track;
  final Album? album;
  final Artist? artist;
  final Playlist? playlist;

  const TopResult._({
    required this.type,
    this.track,
    this.album,
    this.artist,
    this.playlist,
  });

  factory TopResult.track(Track track) =>
      TopResult._(type: SearchResultType.track, track: track);
  factory TopResult.album(Album album) =>
      TopResult._(type: SearchResultType.album, album: album);
  factory TopResult.artist(Artist artist) =>
      TopResult._(type: SearchResultType.artist, artist: artist);
  factory TopResult.playlist(Playlist playlist) =>
      TopResult._(type: SearchResultType.playlist, playlist: playlist);
}

/// Enhanced search results with local + online merge support
class EnhancedSearchResults {
  final String query;

  // YouTube Music's "Top Result" - their best guess at intent
  final TopResult? topResult;

  // Online results from YouTube Music (properly classified)
  final List<Track> onlineTracks;
  final List<Album> onlineAlbums;
  final List<Artist> onlineArtists;
  final List<Playlist> onlinePlaylists;

  // Local results (downloaded/library)
  final List<Track> localTracks;

  // Metadata
  final bool hasMore;
  final DateTime fetchedAt;

  const EnhancedSearchResults({
    required this.query,
    this.topResult,
    this.onlineTracks = const [],
    this.onlineAlbums = const [],
    this.onlineArtists = const [],
    this.onlinePlaylists = const [],
    this.localTracks = const [],
    this.hasMore = false,
    required this.fetchedAt,
  });

  /// Check if online results are empty
  bool get isOnlineEmpty =>
      onlineTracks.isEmpty &&
      onlineAlbums.isEmpty &&
      onlineArtists.isEmpty &&
      onlinePlaylists.isEmpty;

  /// Check if all results are empty
  bool get isEmpty => isOnlineEmpty && localTracks.isEmpty;

  /// Get total online result count
  int get onlineCount =>
      onlineTracks.length +
      onlineAlbums.length +
      onlineArtists.length +
      onlinePlaylists.length;

  /// Create empty results
  factory EnhancedSearchResults.empty(String query) {
    return EnhancedSearchResults(query: query, fetchedAt: DateTime.now());
  }

  /// Merge with local tracks
  EnhancedSearchResults withLocalTracks(List<Track> tracks) {
    return EnhancedSearchResults(
      query: query,
      topResult: topResult,
      onlineTracks: onlineTracks,
      onlineAlbums: onlineAlbums,
      onlineArtists: onlineArtists,
      onlinePlaylists: onlinePlaylists,
      localTracks: tracks,
      hasMore: hasMore,
      fetchedAt: fetchedAt,
    );
  }
}

/// OuterTune-style search service
///
/// Design principles:
/// 1. Delegate search to YouTube Music (InnerTube) - they handle intent detection
/// 2. Properly classify results by type
/// 3. Filter out non-music noise (shorts, videos without music)
/// 4. Support local + online result merging
/// 5. No custom ranking - trust YouTube's results
class SearchService {
  final InnerTubeService _innerTube;

  SearchService(this._innerTube);

  /// Search with proper type classification
  ///
  /// This delegates to YouTube Music and lets them handle:
  /// - Intent detection (artist vs song vs album)
  /// - Typo correction
  /// - Popularity ranking
  /// - Alias/alternate spelling handling
  Future<EnhancedSearchResults> search(
    String query, {
    SearchFilter filter = SearchFilter.all,
    List<Track>? localLibrary,
  }) async {
    if (query.trim().isEmpty) {
      return EnhancedSearchResults.empty(query);
    }

    // Get filter params for specific searches
    final filterParams = _getFilterParams(filter);

    // Fetch from YouTube Music
    final results = await _innerTube.search(query, filter: filterParams);

    // Use YouTube's actual top result if available
    TopResult? topResult;
    if (results.topResult != null) {
      // Convert SearchResultItem to TopResult
      final ytTop = results.topResult!;
      switch (ytTop.type) {
        case SearchResultType.track:
          topResult = TopResult.track(ytTop.track!);
        case SearchResultType.album:
          topResult = TopResult.album(ytTop.album!);
        case SearchResultType.artist:
          topResult = TopResult.artist(ytTop.artist!);
        case SearchResultType.playlist:
          topResult = TopResult.playlist(ytTop.playlist!);
      }
    } else {
      // Fallback: use first item from results
      if (results.tracks.isNotEmpty) {
        topResult = TopResult.track(results.tracks.first);
      } else if (results.artists.isNotEmpty) {
        topResult = TopResult.artist(results.artists.first);
      } else if (results.albums.isNotEmpty) {
        topResult = TopResult.album(results.albums.first);
      } else if (results.playlists.isNotEmpty) {
        topResult = TopResult.playlist(results.playlists.first);
      }
    }

    // Search local library if provided (uses isolate for large libraries)
    List<Track> localMatches = [];
    if (localLibrary != null && localLibrary.isNotEmpty) {
      localMatches = await _searchLocalTracks(query, localLibrary);
    }

    if (kDebugMode) {
      print(
        'Search "$query": ${results.tracks.length} songs, '
        '${results.albums.length} albums, ${results.artists.length} artists, '
        '${results.playlists.length} playlists, ${localMatches.length} local',
      );
    }

    return EnhancedSearchResults(
      query: query,
      topResult: topResult,
      onlineTracks: results.tracks,
      onlineAlbums: results.albums,
      onlineArtists: results.artists,
      onlinePlaylists: results.playlists,
      localTracks: localMatches,
      hasMore: results.hasMore,
      fetchedAt: DateTime.now(),
    );
  }

  /// Get search suggestions from YouTube Music
  /// These are YouTube's autocomplete predictions
  Future<List<String>> getSuggestions(String query) async {
    if (query.trim().isEmpty) return [];
    return _innerTube.getSearchSuggestions(query);
  }

  /// Search local tracks by query
  /// Uses isolate for large libraries to prevent UI jank
  Future<List<Track>> _searchLocalTracks(
    String query,
    List<Track> tracks,
  ) async {
    // For small libraries, run on main thread (isolate overhead not worth it)
    if (tracks.length < 500) {
      return _searchLocalTracksSync(query, tracks);
    }

    // For large libraries, use isolate
    return compute(
      _searchLocalTracksIsolate,
      _LocalSearchParams(query, tracks),
    );
  }

  /// Sync version for small libraries
  static List<Track> _searchLocalTracksSync(String query, List<Track> tracks) {
    final queryLower = query.toLowerCase();
    return tracks.where((track) {
      return track.title.toLowerCase().contains(queryLower) ||
          track.artist.toLowerCase().contains(queryLower) ||
          (track.album?.toLowerCase().contains(queryLower) ?? false);
    }).toList();
  }

  /// Get InnerTube filter params for specific search types
  String? _getFilterParams(SearchFilter filter) {
    // YouTube Music filter params (from InnerTube API)
    switch (filter) {
      case SearchFilter.all:
        return null; // No filter = mixed results
      case SearchFilter.songs:
        return 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D'; // Songs filter
      case SearchFilter.albums:
        return 'EgWKAQIYAWoKEAkQBRAKEAMQBA%3D%3D'; // Albums filter
      case SearchFilter.artists:
        return 'EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D'; // Artists filter
      case SearchFilter.playlists:
        return 'EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D'; // Playlists filter
      case SearchFilter.videos:
        return 'EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D'; // Videos filter
    }
  }
}

/// Parameters for isolate-based local search
class _LocalSearchParams {
  final String query;
  final List<Track> tracks;
  _LocalSearchParams(this.query, this.tracks);
}

/// Isolate function for searching local tracks
/// Top-level function required for compute()
List<Track> _searchLocalTracksIsolate(_LocalSearchParams params) {
  final queryLower = params.query.toLowerCase();
  return params.tracks.where((track) {
    return track.title.toLowerCase().contains(queryLower) ||
        track.artist.toLowerCase().contains(queryLower) ||
        (track.album?.toLowerCase().contains(queryLower) ?? false);
  }).toList();
}
