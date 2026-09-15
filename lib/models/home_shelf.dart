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
  final Duration? duration;
  final String? album;
  final String? albumId;
  final bool isExplicit;

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
    this.duration,
    this.album,
    this.albumId,
    this.isExplicit = false,
  });

  @override
  List<Object?> get props => [
        id,
        title,
        subtitle,
        thumbnailUrl,
        navigationId,
        itemType,
        description,
        playlistId,
        videoId,
        artistId,
        duration,
        album,
        albumId,
        isExplicit,
      ];

  /// Convert to Track if it's a song
  Track? toTrack() {
    if (itemType != HomeShelfItemType.song &&
        (itemType != HomeShelfItemType.podcast || videoId == null)) {
      return null;
    }
    final artistName = _extractArtistFromSubtitle(subtitle);
    final resolvedDuration = duration ?? _extractDurationFromSubtitle(subtitle);
    return Track(
      id: videoId ?? id,
      title: title,
      artist: artistName,
      artistId: artistId ?? '',
      album: album,
      albumId: albumId,
      thumbnailUrl: thumbnailUrl,
      duration: resolvedDuration ?? Duration.zero,
      isExplicit: isExplicit,
    );
  }

  static String _extractArtistFromSubtitle(String? subtitle) {
    final raw = subtitle?.trim();
    if (raw == null || raw.isEmpty) return 'Unknown Artist';

    // Handle both proper bullets and mojibake bullets.
    final normalized = raw.replaceAll('â€¢', '•');
    final parts = normalized
        .split(RegExp(r'\s*[•·|]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    const ignoredTokens = {
      'song',
      'songs',
      'video',
      'videos',
      'track',
      'single',
      'album',
      'artist',
      'explicit',
      'e',
    };

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (ignoredTokens.contains(lower)) continue;
      // Duration token (e.g. 3:20 or 1:05:30)
      if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(part)) continue;
      // Year token (e.g. 2024)
      if (RegExp(r'^\d{4}$').hasMatch(part)) continue;
      // Views token (e.g. 1.2M views, 500K plays)
      if (RegExp(r'^\d+(\.\d+)?[kmb]?\s+(views|plays)$', caseSensitive: false)
          .hasMatch(part)) {
        continue;
      }

      return part;
    }

    return parts.isNotEmpty ? parts.first : raw;
  }

  static Duration? _extractDurationFromSubtitle(String? subtitle) {
    if (subtitle == null) return null;
    final match =
        RegExp(r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})').firstMatch(subtitle);
    if (match == null) return null;

    final hours = match.group(1) != null ? int.parse(match.group(1)!) : 0;
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);

    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  /// Convert to Playlist if it's a playlist/mix/podcast
  Playlist? toPlaylist() {
    if (itemType != HomeShelfItemType.playlist &&
        itemType != HomeShelfItemType.mix &&
        itemType != HomeShelfItemType.podcast) {
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
    if (album != null) 'album': album,
    if (albumId != null) 'albumId': albumId,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
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
    album: json['album'] as String?,
    albumId: json['albumId'] as String?,
    duration: json['durationMs'] != null
        ? Duration(milliseconds: json['durationMs'] as int)
        : null,
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
  final String? headerThumbnailUrl; // Optional header avatar/artwork
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
    this.headerThumbnailUrl,
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
            item.itemType == HomeShelfItemType.mix ||
            item.itemType == HomeShelfItemType.podcast,
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
    'headerThumbnailUrl': headerThumbnailUrl,
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
    headerThumbnailUrl: json['headerThumbnailUrl'] as String?,
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

class WatchRelatedContent extends Equatable {
  final List<HomeShelf> shelves;
  final String? aboutTitle;
  final String? aboutDescription;

  const WatchRelatedContent({
    required this.shelves,
    this.aboutTitle,
    this.aboutDescription,
  });

  static const empty = WatchRelatedContent(shelves: []);

  bool get hasAboutSection =>
      aboutDescription != null && aboutDescription!.trim().isNotEmpty;

  bool get isEmpty => shelves.isEmpty && !hasAboutSection;

  @override
  List<Object?> get props => [shelves, aboutTitle, aboutDescription];
}
