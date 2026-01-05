import 'dart:async';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import '../models/models.dart';
import '../services/services.dart';
import '../services/audio_player_service.dart' as player;
import '../services/album_color_extractor.dart';
export '../services/album_color_extractor.dart' show AlbumColors;
import 'repository_providers.dart';
import 'ytmusic_providers.dart'
    show
        innerTubeServiceProvider,
        ytMusicAuthStateProvider,
        ytMusicLikedSongsProvider;
import '../../../core/services/result.dart';
import '../data/repositories/music_repository.dart'
    show CacheAnalytics, MusicRepository;
import '../data/sources/music_local_source.dart';
import '../core/services/cache/hive_service.dart';
import '../data/entities/color_cache_entity.dart';

/// Provider for the audio handler (initialized once)
final audioHandlerProvider = Provider<InzxAudioHandler?>((ref) {
  // Will be set after initialization in main.dart
  return null;
});

/// Provider for the audio handler initialization
final audioHandlerInitProvider = FutureProvider<InzxAudioHandler>((ref) async {
  return await initAudioService();
});

/// Provider for the YouTube music service
final youtubeServiceProvider = Provider<YouTubeMusicService>((ref) {
  return YouTubeMusicService();
});

/// Provider for the audio player service
/// This is a singleton that gets the InnerTubeService injected
/// The InnerTubeService is shared so auth updates are reflected automatically
final audioPlayerServiceProvider = Provider<player.AudioPlayerService>((ref) {
  final innerTubeService = ref.watch(innerTubeServiceProvider);
  final playerService = player.AudioPlayerService();
  // Inject authenticated InnerTubeService for personalized radio
  playerService.setInnerTubeService(innerTubeService);

  // Listen to auth state changes and refresh when auth changes
  // Use fireImmediately: false to prevent modification during initialization
  ref.listen(ytMusicAuthStateProvider, (previous, next) {
    if (previous?.isLoggedIn != next.isLoggedIn) {
      if (kDebugMode) {
        print('AudioPlayerService: Auth state changed, refreshing...');
      }
      playerService.refreshAuthState();
    }
  }, fireImmediately: false);

  return playerService;
});

/// Provider for current playback state
/// WARNING: This updates frequently (every 500ms for position).
/// For better performance, use specific providers below instead.
final playbackStateProvider = StreamProvider<player.PlaybackState>((ref) {
  final playerService = ref.watch(audioPlayerServiceProvider);
  // Use distinct() to only emit when state actually changes (based on == override)
  return playerService.stateStream.distinct();
});

/// Provider for position stream (for progress bars only)
/// Use this instead of playbackStateProvider when you only need position
final positionStreamProvider = StreamProvider<Duration>((ref) {
  final playerService = ref.watch(audioPlayerServiceProvider);
  return playerService.positionStream;
});

/// Provider for buffered position stream
final bufferedPositionStreamProvider = StreamProvider<Duration>((ref) {
  final playerService = ref.watch(audioPlayerServiceProvider);
  return playerService.bufferedPositionStream;
});

/// Provider for current track ID only (very lightweight, for checking if a track is playing)
final currentTrackIdProvider = Provider<String?>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.currentTrack?.id);
});

/// Provider for current track (only updates when track changes)
final currentTrackProvider = Provider<Track?>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.currentTrack);
});

/// Provider for whether music is playing (only updates on play/pause)
final isPlayingProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.isPlaying) ?? false;
});

/// Provider for current queue
final queueProvider = Provider<List<Track>>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.queue) ?? [];
});

/// Provider for queue source ID (playlist/album/artist ID that started the queue)
final queueSourceIdProvider = Provider<String?>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.queueSourceId);
});

/// Provider for radio mode state (whether infinite queue is active)
final isRadioModeProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.isRadioMode) ?? false;
});

/// Provider for whether radio tracks are currently being fetched
final isFetchingRadioProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.isFetchingRadio) ?? false;
});

/// Provider for dynamic album colors - updates when track changes
/// Used across the app for dynamic theming (mini player, now playing, etc.)
final albumColorsProvider =
    StateNotifierProvider<AlbumColorsNotifier, AlbumColors>((ref) {
      final notifier = AlbumColorsNotifier();

      // Listen to track changes and extract colors automatically
      // Use fireImmediately: false to prevent modification during initialization
      ref.listen<Track?>(currentTrackProvider, (previous, next) {
        if (next != null && next.thumbnailUrl != previous?.thumbnailUrl) {
          notifier.updateForTrack(next);
        }
      }, fireImmediately: false);

      // Schedule initial color extraction after provider is fully initialized
      Future.microtask(() {
        final currentTrack = ref.read(currentTrackProvider);
        if (currentTrack != null) {
          notifier.updateForTrack(currentTrack);
        }
      });

      return notifier;
    });

/// Notifier for album colors extraction
class AlbumColorsNotifier extends StateNotifier<AlbumColors> {
  AlbumColorsNotifier() : super(AlbumColors.defaultColors());

  Future<void> updateForTrack(Track track) async {
    final colors = await AlbumColorExtractor.extractFromUrl(track.thumbnailUrl);
    state = colors;
  }

  void reset() {
    state = AlbumColors.defaultColors();
  }
}

/// Provider for per-track colors (used by shelf items)
/// Caches colors permanently since they don't change for a given image
final trackColorsProvider = FutureProvider.autoDispose
    .family<AlbumColors, String?>((ref, thumbnailUrl) async {
      if (thumbnailUrl == null) return AlbumColors.defaultColors();

      // Check cache first (permanent cache - colors don't change)
      try {
        final cached = HiveService.colorsBox.get(thumbnailUrl);
        if (cached != null) {
          CacheAnalytics.instance.recordCacheHit();
          return AlbumColors(
            accent: Color(cached.accent),
            accentLight: Color(cached.accentLight),
            accentDark: Color(cached.accentDark),
            backgroundPrimary: Color(cached.backgroundPrimary),
            backgroundSecondary: Color(cached.backgroundSecondary),
            surface: Color(cached.surface),
            onBackground: Color(cached.onBackground),
            onSurface: Color(cached.onSurface),
            isDefault: false,
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('trackColorsProvider: Cache load error: $e');
        }
      }

      // Extract from image (cache miss)
      CacheAnalytics.instance.recordCacheMiss();
      final colors = await AlbumColorExtractor.extractFromUrl(thumbnailUrl);

      // Save to cache (permanent)
      try {
        HiveService.colorsBox.put(
          thumbnailUrl,
          ColorCacheEntity(
            imageUrl: thumbnailUrl,
            accent: colors.accent.value,
            accentLight: colors.accentLight.value,
            accentDark: colors.accentDark.value,
            backgroundPrimary: colors.backgroundPrimary.value,
            backgroundSecondary: colors.backgroundSecondary.value,
            surface: colors.surface.value,
            onBackground: colors.onBackground.value,
            onSurface: colors.onSurface.value,
            cachedAt: DateTime.now(),
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          print('trackColorsProvider: Cache save error: $e');
        }
      }

      return colors;
    });

/// Provider for search query
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results
/// Now backed by MusicRepository with intelligent caching
final searchResultsProvider = FutureProvider.autoDispose<SearchResults>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) {
    return SearchResults.empty('');
  }

  // Debounce search
  await Future.delayed(const Duration(milliseconds: 300));

  // Check if query changed during debounce
  if (ref.read(searchQueryProvider) != query) {
    throw Exception('Query changed');
  }

  final repo = ref.watch(musicRepositoryProvider);
  final result = await repo.search(query);
  return switch (result) {
    Success(:final data) => SearchResults(query: query, tracks: data),
    Failure(:final exception) => throw exception,
  };
});

/// Provider for search suggestions
final searchSuggestionsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) {
    return [];
  }

  // Debounce
  await Future.delayed(const Duration(milliseconds: 150));

  if (ref.read(searchQueryProvider) != query) {
    throw Exception('Query changed');
  }

  final ytService = ref.read(youtubeServiceProvider);
  return await ytService.getSearchSuggestions(query);
});

/// Provider for loading related tracks
final relatedTracksProvider = FutureProvider.autoDispose
    .family<List<Track>, String>((ref, videoId) async {
      final ytService = ref.read(youtubeServiceProvider);
      return await ytService.getRelatedTracks(videoId);
    });

/// Provider for loading a playlist
final playlistProvider = FutureProvider.autoDispose.family<Playlist?, String>((
  ref,
  playlistId,
) async {
  final ytService = ref.read(youtubeServiceProvider);
  return await ytService.getPlaylist(playlistId);
});

/// Provider for loading an artist
final artistProvider = FutureProvider.autoDispose.family<Artist?, String>((
  ref,
  channelId,
) async {
  final ytService = ref.read(youtubeServiceProvider);
  return await ytService.getArtist(channelId);
});

/// Provider for trending/discover music
/// Now backed by MusicRepository with intelligent caching
final trendingMusicProvider = FutureProvider<List<Track>>((ref) async {
  final repo = ref.watch(musicRepositoryProvider);
  final result = await repo.getTrendingTracks();
  return result.getOrDefault([]);
});

/// Provider for search history
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier();
    });

/// Notifier for search history
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  static const _maxHistory = 20;

  SearchHistoryNotifier() : super([]);

  void addSearch(String query) {
    if (query.trim().isEmpty) return;

    // Remove if already exists
    final newList = state.where((s) => s != query).toList();

    // Add to front
    newList.insert(0, query);

    // Limit size
    if (newList.length > _maxHistory) {
      newList.removeLast();
    }

    state = newList;
  }

  void removeSearch(String query) {
    state = state.where((s) => s != query).toList();
  }

  void clearHistory() {
    state = [];
  }
}

/// Provider for liked songs
final likedSongsProvider =
    StateNotifierProvider<LikedSongsNotifier, List<Track>>((ref) {
      return LikedSongsNotifier();
    });

/// Notifier for liked songs
class LikedSongsNotifier extends StateNotifier<List<Track>> {
  LikedSongsNotifier() : super([]);

  void toggleLike(Track track) {
    final isLiked = state.any((t) => t.id == track.id);
    if (isLiked) {
      state = state.where((t) => t.id != track.id).toList();
    } else {
      state = [track.copyWith(addedAt: DateTime.now()), ...state];
    }
  }

  /// Add a track to liked songs (if not already liked)
  void like(Track track) {
    final alreadyLiked = state.any((t) => t.id == track.id);
    if (!alreadyLiked) {
      state = [track.copyWith(addedAt: DateTime.now()), ...state];
    }
  }

  bool isLiked(String trackId) {
    return state.any((t) => t.id == trackId);
  }

  void unlike(String trackId) {
    state = state.where((t) => t.id != trackId).toList();
  }
}

/// Provider to track explicitly unliked songs (overrides YT Music cache until refresh)
final explicitlyUnlikedIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Check if a track is liked (from local state OR YT Music backend)
final isTrackLikedProvider = Provider.family<bool, String>((ref, trackId) {
  // First check if explicitly unliked (overrides everything)
  final explicitlyUnliked = ref.watch(explicitlyUnlikedIdsProvider);
  if (explicitlyUnliked.contains(trackId)) {
    return false;
  }

  // Check local liked songs
  final likedSongs = ref.watch(likedSongsProvider);
  if (likedSongs.any((t) => t.id == trackId)) {
    return true;
  }

  // Also check YT Music liked songs if logged in
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (authState.isLoggedIn) {
    final ytLikedAsync = ref.watch(ytMusicLikedSongsProvider);

    // Check loading state
    if (ytLikedAsync.isLoading) {
      // Still loading - return false for now but will rebuild when data arrives
      return false;
    }

    final ytLikedSongs = ytLikedAsync.valueOrNull ?? [];
    final isLiked = ytLikedSongs.any((t) => t.id == trackId);

    // Debug: Always log the check
    if (kDebugMode) {
      print(
        'isTrackLiked: "$trackId" -> found=$isLiked (total liked: ${ytLikedSongs.length})',
      );
    }

    return isLiked;
  }

  return false;
});

/// Provider for liked songs from YouTube Music backend
/// Returns cached liked songs with intelligent cache strategy
final likedSongsRepositoryProvider = FutureProvider<List<Track>>((ref) async {
  final repo = ref.watch(musicRepositoryProvider);
  final result = await repo.getLikedSongs();
  return result.getOrDefault([]);
});

/// Provider for recently played tracks
final recentlyPlayedProvider =
    StateNotifierProvider<RecentlyPlayedNotifier, List<Track>>((ref) {
      return RecentlyPlayedNotifier();
    });

/// Notifier for recently played
class RecentlyPlayedNotifier extends StateNotifier<List<Track>> {
  static const _maxRecent = 50;

  RecentlyPlayedNotifier() : super([]);

  void addTrack(Track track) {
    // Remove if already exists
    final newList = state.where((t) => t.id != track.id).toList();

    // Add to front
    newList.insert(0, track);

    // Limit size
    if (newList.length > _maxRecent) {
      newList.removeLast();
    }

    state = newList;
  }

  void clearHistory() {
    state = [];
  }
}

/// Provider for local playlists
final localPlaylistsProvider =
    StateNotifierProvider<LocalPlaylistsNotifier, List<Playlist>>((ref) {
      return LocalPlaylistsNotifier();
    });

/// Notifier for local playlists
class LocalPlaylistsNotifier extends StateNotifier<List<Playlist>> {
  LocalPlaylistsNotifier() : super([]);

  void createPlaylist(String name, {String? description}) {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: name,
      description: description,
      isLocal: true,
      tracks: [],
      trackCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    state = [playlist, ...state];
  }

  void deletePlaylist(String playlistId) {
    state = state.where((p) => p.id != playlistId).toList();
  }

  void renamePlaylist(String playlistId, String newName) {
    state = state.map((p) {
      if (p.id == playlistId) {
        return p.copyWith(title: newName, updatedAt: DateTime.now());
      }
      return p;
    }).toList();
  }

  void addTrackToPlaylist(String playlistId, Track track) {
    state = state.map((p) {
      if (p.id == playlistId) {
        final List<Track> tracks = [...(p.tracks ?? <Track>[]), track];
        return p.copyWith(
          tracks: tracks,
          trackCount: tracks.length,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
  }

  void removeTrackFromPlaylist(String playlistId, String trackId) {
    state = state.map((p) {
      if (p.id == playlistId) {
        final tracks = (p.tracks ?? []).where((t) => t.id != trackId).toList();
        return p.copyWith(
          tracks: tracks,
          trackCount: tracks.length,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
  }
}

/// Provider for shuffle state
final shuffleEnabledProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.shuffleEnabled) ?? false;
});

/// Provider for repeat/loop mode
final loopModeProvider = Provider<LoopMode>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.loopMode) ?? LoopMode.off;
});

/// Provider for audio quality setting
final audioQualityProvider = Provider<AudioQuality>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.audioQuality) ?? AudioQuality.auto;
});

/// Provider for playback speed
final playbackSpeedProvider = Provider<double>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.speed) ?? 1.0;
});

/// Provider for current stream quality info
final streamQualityInfoProvider = Provider<String>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.qualityInfo) ?? '';
});

/// Provider for current playback data (stream info)
final currentPlaybackDataProvider = Provider<PlaybackData?>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenOrNull(data: (s) => s.currentPlaybackData);
});

/// Provider for prefetching tracks (OuterTune-style)
/// Call this when tracks become visible to prefetch their stream URLs
/// This makes play taps instant (pure cache lookup)
final trackPrefetchProvider = Provider<TrackPrefetchManager>((ref) {
  final playerService = ref.watch(audioPlayerServiceProvider);
  return TrackPrefetchManager(playerService);
});

/// Provider for cache management operations
/// Use this to get cache stats, cleanup expired entries, or clear cache
final cacheManagementProvider = Provider<CacheManager>((ref) {
  final repo = ref.watch(musicRepositoryProvider);
  return CacheManager(repo);
});

/// Manager for cache operations
class CacheManager {
  final MusicRepository _repo;

  CacheManager(this._repo);

  /// Get current cache statistics
  Future<CacheStats> getCacheStats() async {
    final result = await _repo.getCacheStats();
    return result.getOrThrow();
  }

  /// Clean up expired cache entries (TTL-based)
  Future<void> cleanupExpiredCache() async {
    await _repo.cleanupExpiredCache();
  }

  /// Clear all cached data
  Future<void> clearAllCache() async {
    await _repo.clearAllCache();
  }
}

/// Manager for prefetching tracks on visibility
/// Keeps track of what's already prefetched to avoid duplicate work
class TrackPrefetchManager {
  final player.AudioPlayerService _playerService;
  final Set<String> _prefetchedIds = {};
  bool _isPrefetching = false;

  TrackPrefetchManager(this._playerService);

  /// Prefetch tracks when they become visible on screen
  /// This is called by home page widgets when shelves are displayed
  void prefetchVisibleTracks(List<Track> tracks) {
    if (tracks.isEmpty || _isPrefetching) return;

    // Filter out already prefetched tracks
    final newTracks = tracks
        .where((t) => !_prefetchedIds.contains(t.id))
        .toList();
    if (newTracks.isEmpty) return;

    // Mark as prefetching (limit to first 20 for performance)
    final toPrefetch = newTracks.take(20).toList();
    for (final track in toPrefetch) {
      _prefetchedIds.add(track.id);
    }

    // Fire and forget - don't block UI
    _isPrefetching = true;
    _playerService
        .prefetchTracks(toPrefetch.map((t) => t.id).toList())
        .then((_) {
          _isPrefetching = false;
        })
        .catchError((e) {
          _isPrefetching = false;
          // Prefetch error - silently ignore to not interrupt user experience
          // ignore: avoid_print
          if (kDebugMode) {
            print('TrackPrefetchManager: Prefetch error: $e');
          }
        });
  }

  /// Check if a track is prefetched (for debugging)
  bool isPrefetched(String trackId) => _prefetchedIds.contains(trackId);

  /// Clear prefetch cache (call on logout or app restart)
  void clear() => _prefetchedIds.clear();
}
