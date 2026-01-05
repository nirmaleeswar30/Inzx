import 'package:flutter/foundation.dart' show kDebugMode, compute;
import '../models/models.dart';
import 'ytmusic_api_service.dart';

/// Represents the type of content entity
enum ArtistEntityType {
  /// A curated YouTube Music artist with albums, singles, etc.
  musicArtist,

  /// A generic YouTube channel with uploads
  channel,
}

/// Represents an artist shelf/section from YouTube Music
enum ArtistShelfType {
  songs,
  albums,
  singles,
  eps,
  appearsOn,
  playlists,
  videos,
  featuredOn,
  fans,
  similar,
  unknown,
}

/// A shelf/section on the artist page
class ArtistShelf {
  final ArtistShelfType type;
  final String title;
  final String? browseId;
  final String? params;
  final List<Track> tracks;
  final List<Album> albums;
  final List<Playlist> playlists;
  final List<Artist> artists;
  final bool hasMore;

  const ArtistShelf({
    required this.type,
    required this.title,
    this.browseId,
    this.params,
    this.tracks = const [],
    this.albums = const [],
    this.playlists = const [],
    this.artists = const [],
    this.hasMore = false,
  });

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && playlists.isEmpty && artists.isEmpty;
}

/// Enhanced artist data with all shelves from YouTube Music
class ArtistPageData {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final String? description;
  final int? subscriberCount;
  final ArtistEntityType entityType;

  /// Shelves returned by YouTube Music (in order)
  final List<ArtistShelf> shelves;

  /// Primary navigation endpoints
  final String? playEndpoint;
  final String? shuffleEndpoint;
  final String? radioEndpoint;

  /// Local tracks by this artist (merged, not blended into YTM data)
  final List<Track> localTracks;

  /// Fetch timestamp for cache management
  final DateTime fetchedAt;

  const ArtistPageData({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.bannerUrl,
    this.description,
    this.subscriberCount,
    this.entityType = ArtistEntityType.musicArtist,
    this.shelves = const [],
    this.playEndpoint,
    this.shuffleEndpoint,
    this.radioEndpoint,
    this.localTracks = const [],
    required this.fetchedAt,
  });

  /// Get a specific shelf by type
  ArtistShelf? getShelf(ArtistShelfType type) {
    try {
      return shelves.firstWhere((s) => s.type == type);
    } catch (_) {
      return null;
    }
  }

  /// Get top songs (convenience getter)
  List<Track> get topTracks => getShelf(ArtistShelfType.songs)?.tracks ?? [];

  /// Get albums (convenience getter)
  List<Album> get albums => getShelf(ArtistShelfType.albums)?.albums ?? [];

  /// Get singles (convenience getter)
  List<Album> get singles => getShelf(ArtistShelfType.singles)?.albums ?? [];

  /// Check if this is a music artist (vs generic channel)
  bool get isMusicArtist => entityType == ArtistEntityType.musicArtist;

  /// Create empty artist data
  factory ArtistPageData.empty(String id) {
    return ArtistPageData(
      id: id,
      name: 'Unknown Artist',
      fetchedAt: DateTime.now(),
    );
  }

  /// Add local tracks (returns new instance)
  ArtistPageData withLocalTracks(List<Track> tracks) {
    return ArtistPageData(
      id: id,
      name: name,
      thumbnailUrl: thumbnailUrl,
      bannerUrl: bannerUrl,
      description: description,
      subscriberCount: subscriberCount,
      entityType: entityType,
      shelves: shelves,
      playEndpoint: playEndpoint,
      shuffleEndpoint: shuffleEndpoint,
      radioEndpoint: radioEndpoint,
      localTracks: tracks,
      fetchedAt: fetchedAt,
    );
  }
}

/// OuterTune-style artist service
///
/// Design principles:
/// 1. Use browseId, not artist names
/// 2. Distinguish music artists from generic channels
/// 3. Render YTM shelves faithfully (don't invent structure)
/// 4. Support pagination via continuation tokens
/// 5. Local tracks are additive, not merged into YTM albums
/// 6. Light caching (artist content changes frequently)
class ArtistService {
  final InnerTubeService _innerTube;

  ArtistService(this._innerTube);

  /// Fetch artist page data
  ///
  /// Uses browseId to fetch directly from YouTube Music.
  /// The response includes structured shelves that we render faithfully.
  Future<ArtistPageData> getArtist(
    String browseId, {
    List<Track>? localLibrary,
  }) async {
    // Determine if this is an artist or channel
    // Artists typically have UC prefix for their channel ID
    final entityType = browseId.startsWith('UC')
        ? ArtistEntityType.musicArtist
        : ArtistEntityType.channel;

    // Fetch from InnerTube
    final artist = await _innerTube.getArtist(browseId);

    if (artist == null) {
      return ArtistPageData.empty(browseId);
    }

    // Build shelves from artist data
    final shelves = <ArtistShelf>[];

    // Songs shelf
    if (artist.topTracks != null && artist.topTracks!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.songs,
          title: 'Songs',
          tracks: artist.topTracks!,
          browseId: artist.songsBrowseId,
          params: artist.songsParams,
          hasMore: artist.songsBrowseId != null,
        ),
      );
    }

    // Albums shelf (from parsed albums)
    if (artist.albums != null && artist.albums!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.albums,
          title: 'Albums',
          albums: artist.albums!,
        ),
      );
    }

    // Singles & EPs shelf (from parsed singles)
    if (artist.singles != null && artist.singles!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.singles,
          title: 'Singles & EPs',
          albums: artist.singles!,
        ),
      );
    }

    // Appears On shelf
    if (artist.appearsOn != null && artist.appearsOn!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.appearsOn,
          title: 'Appears On',
          albums: artist.appearsOn!,
        ),
      );
    }

    // Playlists shelf
    if (artist.playlists != null && artist.playlists!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.playlists,
          title: 'Playlists',
          playlists: artist.playlists!,
        ),
      );
    }

    // Similar artists shelf
    if (artist.similarArtists != null && artist.similarArtists!.isNotEmpty) {
      shelves.add(
        ArtistShelf(
          type: ArtistShelfType.similar,
          title: 'Fans Also Like',
          artists: artist.similarArtists!,
        ),
      );
    }

    // Search local library for tracks by this artist (isolate for large libraries)
    List<Track> localMatches = [];
    if (localLibrary != null && localLibrary.isNotEmpty) {
      localMatches = await _searchArtistTracks(
        artist.name,
        browseId,
        localLibrary,
      );
    }

    if (kDebugMode) {
      print(
        'ArtistService: Fetched ${artist.name} - '
        '${shelves.length} shelves, ${localMatches.length} local tracks',
      );
    }

    return ArtistPageData(
      id: browseId,
      name: artist.name,
      thumbnailUrl: artist.thumbnailUrl,
      description: artist.description,
      subscriberCount: artist.subscriberCount,
      entityType: entityType,
      shelves: shelves,
      localTracks: localMatches,
      fetchedAt: DateTime.now(),
    );
  }

  /// Load more items for a shelf (pagination)
  Future<List<Track>> loadMoreSongs(
    String browseId,
    String? params, {
    String? continuationToken,
  }) async {
    if (browseId.isEmpty) return [];

    final result = await _innerTube.browseShelf(
      browseId,
      params: params,
      continuationToken: continuationToken,
    );

    // Extract tracks from shelf items
    return result.items
        .where(
          (item) =>
              item.itemType == HomeShelfItemType.song && item.videoId != null,
        )
        .map(
          (item) => Track(
            id: item.videoId!,
            title: item.title,
            artist: item.subtitle ?? 'Unknown Artist',
            duration: Duration.zero,
            thumbnailUrl: item.thumbnailUrl,
          ),
        )
        .toList();
  }

  /// Search local tracks by artist - uses isolate for large libraries
  Future<List<Track>> _searchArtistTracks(
    String artistName,
    String artistId,
    List<Track> tracks,
  ) async {
    // For small libraries, run on main thread
    if (tracks.length < 500) {
      return _searchArtistTracksSync(artistName, artistId, tracks);
    }

    // For large libraries, use isolate
    return compute(
      _searchArtistTracksIsolate,
      _ArtistSearchParams(artistName, artistId, tracks),
    );
  }

  /// Sync version for small libraries
  static List<Track> _searchArtistTracksSync(
    String artistName,
    String artistId,
    List<Track> tracks,
  ) {
    final artistNameLower = artistName.toLowerCase();
    return tracks
        .where(
          (track) =>
              track.artist.toLowerCase().contains(artistNameLower) ||
              track.artistId == artistId,
        )
        .toList();
  }
}

/// Parameters for isolate-based artist track search
class _ArtistSearchParams {
  final String artistName;
  final String artistId;
  final List<Track> tracks;
  _ArtistSearchParams(this.artistName, this.artistId, this.tracks);
}

/// Isolate function for searching artist tracks
List<Track> _searchArtistTracksIsolate(_ArtistSearchParams params) {
  final artistNameLower = params.artistName.toLowerCase();
  return params.tracks
      .where(
        (track) =>
            track.artist.toLowerCase().contains(artistNameLower) ||
            track.artistId == params.artistId,
      )
      .toList();
}
