import 'package:equatable/equatable.dart';
import 'track.dart';
import 'album_artist_playlist.dart';

/// Type of content in a home shelf
enum HomeShelfType {
  quickPicks, // Radio-based song selection
  mixedForYou, // Personalized mixes (Supermix, My Mix 1-7)
  discoverMix, // New songs from artists you might like
  newReleaseMix, // New tracks from artists you follow
  similarToArtist, // Similar to [Artist] suggestions
  newReleases, // Recently released albums
  forgottenFavorites, // Songs you used to listen to
  charts, // Top charts
  moods, // Mood-based playlists
  genres, // Genre-based shelves
  artists, // Artist suggestions
  videos, // Recommended music videos
  podcasts, // Long listening content
  samples, // Shorts-style vertical videos
  listenAgain, // Recently played
  trending, // Trending content
  unknown, // Fallback
}

/// Represents a single item in a home shelf
class HomeShelfItem extends Equatable {
  final String id;
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final String?
  navigationId; // browseId for playlists/albums, videoId for tracks
  final HomeShelfItemType itemType;
  final String? description;
  final String? playlistId; // For playable playlists
  final String? videoId; // For playable tracks
  final String? artistId; // Artist channel ID for "Go to Artist" navigation

  const HomeShelfItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.navigationId,
    required this.itemType,
    this.description,
    this.playlistId,
    this.videoId,
    this.artistId,
  });

  @override
  List<Object?> get props => [id];

  /// Convert to Track if it's a song
  Track? toTrack() {
    if (itemType != HomeShelfItemType.song) return null;
    return Track(
      id: videoId ?? id,
      title: title,
      artist: subtitle ?? 'Unknown Artist',
      artistId: artistId ?? '',
      thumbnailUrl: thumbnailUrl,
      duration: Duration.zero,
    );
  }

  /// Convert to Playlist if it's a playlist/mix
  Playlist? toPlaylist() {
    if (itemType != HomeShelfItemType.playlist &&
        itemType != HomeShelfItemType.mix) {
      return null;
    }
    return Playlist(
      id: playlistId ?? navigationId ?? id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      trackCount: 0,
      isYTMusic: true,
    );
  }

  /// Convert to Album if it's an album
  Album? toAlbum() {
    if (itemType != HomeShelfItemType.album) return null;
    return Album(
      id: navigationId ?? id,
      title: title,
      artist: subtitle ?? 'Unknown Artist',
      thumbnailUrl: thumbnailUrl,
      isYTMusic: true,
    );
  }

  /// Convert to Artist if it's an artist
  Artist? toArtist() {
    if (itemType != HomeShelfItemType.artist) return null;
    return Artist(
      id: navigationId ?? id,
      name: title,
      thumbnailUrl: thumbnailUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'thumbnailUrl': thumbnailUrl,
    'navigationId': navigationId,
    'itemType': itemType.name,
    'description': description,
    'playlistId': playlistId,
    'videoId': videoId,
    'artistId': artistId,
  };

  factory HomeShelfItem.fromJson(Map<String, dynamic> json) => HomeShelfItem(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    navigationId: json['navigationId'] as String?,
    itemType: HomeShelfItemType.values.firstWhere(
      (e) => e.name == json['itemType'],
      orElse: () => HomeShelfItemType.unknown,
    ),
    description: json['description'] as String?,
    playlistId: json['playlistId'] as String?,
    videoId: json['videoId'] as String?,
    artistId: json['artistId'] as String?,
  );
}

/// Type of item within a shelf
enum HomeShelfItemType {
  song,
  album,
  playlist,
  mix, // Personalized mix (Supermix, My Mix, etc.)
  artist,
  video,
  podcast,
  sample, // Shorts-style content
  chart,
  mood,
  genre,
  unknown,
}

/// Represents a horizontal shelf/carousel on the home page
class HomeShelf extends Equatable {
  final String id;
  final String title;
  final String? subtitle;
  final HomeShelfType type;
  final List<HomeShelfItem> items;
  final bool isPlayable; // Can the entire shelf be played as a playlist?
  final String? playlistId; // Playlist ID if playable
  final String? strapline; // Small text above title
  final String? browseId; // For "See all" navigation
  final String?
  params; // Required params for some browse endpoints (e.g., artist songs)

  const HomeShelf({
    required this.id,
    required this.title,
    this.subtitle,
    required this.type,
    required this.items,
    this.isPlayable = false,
    this.playlistId,
    this.strapline,
    this.browseId,
    this.params,
  });

  /// Check if this is a personalized mix shelf (My Supermix, My Mix 1-7, etc.)
  bool get isMixShelf =>
      type == HomeShelfType.mixedForYou ||
      type == HomeShelfType.discoverMix ||
      type == HomeShelfType.newReleaseMix;

  /// Check if this is a Quick Picks shelf
  bool get isQuickPicks => type == HomeShelfType.quickPicks;

  /// Get all items as tracks (for Quick Picks)
  List<Track> get tracks => items
      .where((item) => item.itemType == HomeShelfItemType.song)
      .map((item) => item.toTrack())
      .whereType<Track>()
      .toList();

  /// Get all items as playlists (for mix shelves)
  List<Playlist> get playlists => items
      .where(
        (item) =>
            item.itemType == HomeShelfItemType.playlist ||
            item.itemType == HomeShelfItemType.mix,
      )
      .map((item) => item.toPlaylist())
      .whereType<Playlist>()
      .toList();

  /// Get all items as albums
  List<Album> get albums => items
      .where((item) => item.itemType == HomeShelfItemType.album)
      .map((item) => item.toAlbum())
      .whereType<Album>()
      .toList();

  /// Get all items as artists
  List<Artist> get artists => items
      .where((item) => item.itemType == HomeShelfItemType.artist)
      .map((item) => item.toArtist())
      .whereType<Artist>()
      .toList();

  @override
  List<Object?> get props => [id];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'type': type.name,
    'items': items.map((e) => e.toJson()).toList(),
    'isPlayable': isPlayable,
    'playlistId': playlistId,
    'strapline': strapline,
    'browseId': browseId,
    'params': params,
  };

  factory HomeShelf.fromJson(Map<String, dynamic> json) => HomeShelf(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    type: HomeShelfType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => HomeShelfType.unknown,
    ),
    items: (json['items'] as List)
        .map((e) => HomeShelfItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    isPlayable: json['isPlayable'] as bool? ?? false,
    playlistId: json['playlistId'] as String?,
    strapline: json['strapline'] as String?,
    browseId: json['browseId'] as String?,
    params: json['params'] as String?,
  );
}

/// Container for all home page content
class HomePageContent {
  final List<HomeShelf> shelves;
  final String? continuationToken; // For pagination
  final DateTime fetchedAt;

  const HomePageContent({
    required this.shelves,
    this.continuationToken,
    required this.fetchedAt,
  });

  /// Get Quick Picks shelf
  HomeShelf? get quickPicks =>
      shelves
          .firstWhere(
            (s) => s.type == HomeShelfType.quickPicks,
            orElse: () => const HomeShelf(
              id: '',
              title: '',
              type: HomeShelfType.unknown,
              items: [],
            ),
          )
          .items
          .isEmpty
      ? null
      : shelves.firstWhere((s) => s.type == HomeShelfType.quickPicks);

  /// Get personalized mixes
  List<HomeShelf> get mixes => shelves.where((s) => s.isMixShelf).toList();

  /// Get new releases shelf
  HomeShelf? get newReleases => shelves.cast<HomeShelf?>().firstWhere(
    (s) => s?.type == HomeShelfType.newReleases,
    orElse: () => null,
  );

  /// Get forgotten favorites shelf
  HomeShelf? get forgottenFavorites => shelves.cast<HomeShelf?>().firstWhere(
    (s) => s?.type == HomeShelfType.forgottenFavorites,
    orElse: () => null,
  );

  /// Get listen again shelf
  HomeShelf? get listenAgain => shelves.cast<HomeShelf?>().firstWhere(
    (s) => s?.type == HomeShelfType.listenAgain,
    orElse: () => null,
  );

  /// Get charts
  List<HomeShelf> get charts =>
      shelves.where((s) => s.type == HomeShelfType.charts).toList();

  /// Get mood shelves
  List<HomeShelf> get moods =>
      shelves.where((s) => s.type == HomeShelfType.moods).toList();

  /// Check if content is stale (older than 30 minutes)
  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes > 30;

  /// Empty home page
  static HomePageContent get empty =>
      HomePageContent(shelves: [], fetchedAt: DateTime.now());

  Map<String, dynamic> toJson() => {
    'shelves': shelves.map((e) => e.toJson()).toList(),
    'continuationToken': continuationToken,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory HomePageContent.fromJson(Map<String, dynamic> json) =>
      HomePageContent(
        shelves: (json['shelves'] as List)
            .map((e) => HomeShelf.fromJson(e as Map<String, dynamic>))
            .toList(),
        continuationToken: json['continuationToken'] as String?,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      );
}

/// Result from browsing a shelf (for "More" / "See all" pagination)
class BrowseShelfResult {
  final List<HomeShelfItem> items;
  final String? continuationToken;
  final String? title;

  const BrowseShelfResult({
    required this.items,
    this.continuationToken,
    this.title,
  });

  bool get hasMore => continuationToken != null;
}
