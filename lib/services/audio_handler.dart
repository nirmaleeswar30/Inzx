import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/models.dart';
import 'audio_player_service.dart' as player;
import 'playback/playback.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/cache/hive_service.dart';
import '../data/sources/music_local_source.dart';
import 'ytmusic_api_service.dart';
import 'ytmusic_auth_service.dart';
import '../data/entities/track_entity.dart';
import 'widget_sync_service.dart';
/// Audio handler for background playback and media controls
///
/// This is the Android MediaLibraryService equivalent.
/// It runs independently of UI lifecycle and handles:
/// - Background playback
/// - Notification controls
/// - Media session integration
/// - Audio focus management
///
/// Based on OuterTune's MusicService architecture.
class InzxAudioHandler extends BaseAudioHandler with SeekHandler {
  final player.AudioPlayerService _playerService = player.AudioPlayerService();
  final _ytMusicService = InnerTubeService();

  Future<void> _initAuth() async {
    final authService = YTMusicAuthService(_ytMusicService);
    await authService.restoreCachedAuth();
  }
  StreamSubscription<player.PlaybackState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _bufferedPositionSubscription;
  static const Duration _positionSyncInterval = Duration(seconds: 1);
  String? _lastTrackId;
  int? _lastQueueLength;
  DateTime? _lastPositionSyncAt;

  // Current position for system updates (not from stateStream)
  Duration _currentPosition = Duration.zero;
  Duration _bufferedPosition = Duration.zero;

  InzxAudioHandler() {
    _init();
  }

  void _init() {
    _initAuth();
    // Listen to player service state for track/play state changes
    // Position is handled separately via positionStream
    _stateSubscription = _playerService.stateStream.listen((state) {
      // Update playback state with current position values
      _updatePlaybackState(state);

      // Only update media item when track changes
      if (state.currentTrack?.id != _lastTrackId) {
        _lastTrackId = state.currentTrack?.id;
        _updateMediaItem(state.currentTrack);
      }

      // Only update queue when it changes
      if (state.queue.length != _lastQueueLength) {
        _lastQueueLength = state.queue.length;
        _updateQueue(state.queue);
      }

      unawaited(
        WidgetSyncService.syncPlaybackState(
          state,
          statusLabel: _playerService.isJamsModeEnabled ? 'INZX JAM' : null,
        ),
      );
    });

    // Separate position stream for system UI updates (more frequent)
    _positionSubscription = _playerService.positionStream.listen((position) {
      _currentPosition = position;
      final now = DateTime.now();
      final shouldSyncPosition =
          _lastPositionSyncAt == null ||
          now.difference(_lastPositionSyncAt!) >= _positionSyncInterval;

      if (shouldSyncPosition) {
        _lastPositionSyncAt = now;

        final state = _playerService.state;
        unawaited(
          WidgetSyncService.syncProgress(
            track: state.currentTrack,
            isPlaying: state.isPlaying,
            hasTrack: state.currentTrack != null,
            position: position,
            duration: state.duration,
          ),
        );
      }
    });

    // Buffered position stream
    _bufferedPositionSubscription = _playerService.bufferedPositionStream
        .listen((bufferedPos) {
          _bufferedPosition = bufferedPos;
        });
  }


  void _updatePlaybackState(player.PlaybackState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          state.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(state),
        playing: state.isPlaying,
        updatePosition:
            _currentPosition, // Use tracked position, not state.position
        bufferedPosition: _bufferedPosition,
        speed: state.speed,
        queueIndex: state.currentIndex >= 0 ? state.currentIndex : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(player.PlaybackState state) {
    if (state.error != null) return AudioProcessingState.error;
    if (state.isLoading) return AudioProcessingState.loading;
    if (state.isBuffering) return AudioProcessingState.buffering;
    if (state.currentTrack == null) return AudioProcessingState.idle;
    return AudioProcessingState.ready;
  }

  void _updateMediaItem(Track? track) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }

    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album ?? '',
        duration: track.duration,
        artUri: track.bestThumbnail != null
            ? Uri.parse(track.bestThumbnail!)
            : null,
      ),
    );
  }

  void _updateQueue(List<Track> tracks) {
    queue.add(
      tracks
          .map(
            (track) => MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album ?? '',
              duration: track.duration,
              artUri: track.bestThumbnail != null
                  ? Uri.parse(track.bestThumbnail!)
                  : null,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> play() => _playerService.play();

  @override
  Future<void> pause() => _playerService.pause();

  @override
  Future<void> stop() async {
    await _playerService.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _playerService.seek(position);

  @override
  Future<void> skipToNext() => _playerService.skipToNext();

  @override
  Future<void> skipToPrevious() => _playerService.skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async =>
      _playerService.skipToIndex(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _playerService.setLoopMode(loopMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final shouldShuffle = shuffleMode != AudioServiceShuffleMode.none;
    if (shouldShuffle != _playerService.state.shuffleEnabled) {
      await _playerService.toggleShuffle();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _playerService.setSpeed(speed);

  @override
  Future<void> fastForward() =>
      _playerService.seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() => _playerService.seekBy(const Duration(seconds: -10));

  /// Play a track
  Future<void> playTrack(Track track) => _playerService.playTrack(track);

  /// Play a queue
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) =>
      _playerService.playQueue(tracks, startIndex: startIndex);

  /// Add to queue
  void addToQueue(List<Track> tracks) => _playerService.addToQueue(tracks);

  /// Play next
  void playNext(Track track) => _playerService.playNext(track);

  /// Get current state
  player.PlaybackState get currentState => _playerService.state;

  /// State stream
  Stream<player.PlaybackState> get stateStream => _playerService.stateStream;

  /// Toggle shuffle
  Future<void> toggleShuffle() => _playerService.toggleShuffle();

  /// Cycle loop mode
  Future<void> cycleLoopMode() => _playerService.cycleLoopMode();

  /// Set audio quality preference
  void setAudioQuality(AudioQuality quality) =>
      _playerService.setAudioQuality(quality);

  /// Get current audio quality
  AudioQuality get audioQuality => _playerService.audioQuality;

  /// Get current player state (not to be confused with audio_service's playbackState)
  player.PlaybackState get currentPlayerState => _playerService.state;

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  // ==========================================
  // Android Auto / MediaBrowserService Support
  // ==========================================

  // Content style constants for Android Auto card layout
  static const _groupTitleKey =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        // Root tabs — grid style hints are set globally via
        // AudioServiceConfig.androidBrowsableRootExtras in initAudioService().
        return [
          MediaItem(
            id: 'home',
            title: 'Home',
            playable: false,
            extras: <String, dynamic>{
              AndroidContentStyle.playableHintKey:
                  AndroidContentStyle.gridItemHintValue,
              AndroidContentStyle.browsableHintKey:
                  AndroidContentStyle.gridItemHintValue,
            },
          ),
          MediaItem(
            id: 'recent',
            title: 'History',
            playable: false,
            extras: <String, dynamic>{
              AndroidContentStyle.playableHintKey:
                  AndroidContentStyle.gridItemHintValue,
            },
          ),
          MediaItem(
            id: 'library',
            title: 'Your Library',
            playable: false,
            extras: <String, dynamic>{
              AndroidContentStyle.playableHintKey:
                  AndroidContentStyle.gridItemHintValue,
              AndroidContentStyle.browsableHintKey:
                  AndroidContentStyle.listItemHintValue,
            },
          ),
        ];

      // ── Home ─────────────────────────────────────────────
      case 'home':
        return _buildHomeCards();

      // ── Recently Played ──────────────────────────────────
      case 'recent':
        return _buildRecentCards();

      // ── Your Library ─────────────────────────────────────
      case 'library':
        return _buildLibraryItems();

      // ── Library sub‑pages ────────────────────────────────
      case 'liked_songs':
        try {
          final tracks = await _ytMusicService.getLikedSongs();
          return tracks.map(_trackToMediaItem).toList();
        } catch (_) {
          return [];
        }

      case 'library_playlists':
        try {
          final playlists = await _ytMusicService.getSavedPlaylists();
          return playlists.map((p) => MediaItem(
            id: p.id,
            title: p.title,
            artist: p.author ?? '',
            artUri: p.thumbnailUrl != null ? Uri.parse(p.thumbnailUrl!) : null,
            playable: false,
            extras: <String, dynamic>{
              AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
            },
          )).toList();
        } catch (_) {
          return [];
        }

      case 'library_albums':
        try {
          final albums = await _ytMusicService.getSavedAlbums();
          return albums.map((a) => MediaItem(
            id: a.id,
            title: a.title,
            artist: a.artist,
            artUri: a.bestThumbnail != null ? Uri.parse(a.bestThumbnail!) : null,
            playable: false,
            extras: <String, dynamic>{
              AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
            },
          )).toList();
        } catch (_) {
          return [];
        }

      case 'local_music':
        return HiveService.localMusicTracksBox.values
            .map((e) => _trackToMediaItem(_entityToTrack(e)))
            .toList();

      case 'downloaded':
        return HiveService.tracksBox.values
            .where((t) => t.localFilePath != null)
            .map((e) => _trackToMediaItem(_entityToTrack(e)))
            .toList();

      // ── Shelf drill‑down & fallback ──────────────────────
      default:
        if (parentMediaId.startsWith('shelf_')) {
          return _buildShelfItems(
            parentMediaId.replaceFirst('shelf_', ''),
          );
        } else if (parentMediaId.startsWith('VL') || 
                   parentMediaId.startsWith('PL') || 
                   parentMediaId.startsWith('RD')) {
          try {
            final playlist = await _ytMusicService.getPlaylist(parentMediaId);
            if (playlist != null) {
              return playlist.tracks?.map(_trackToMediaItem).toList() ?? [];
            }
          } catch (e) {
            if (kDebugMode) print('Android Auto Playlist Fetch Error: $e');
          }
        } else if (parentMediaId.startsWith('MPRE')) {
          try {
            final album = await _ytMusicService.getAlbum(parentMediaId);
            if (album != null) {
              return album.tracks?.map(_trackToMediaItem).toList() ?? [];
            }
          } catch (e) {
            if (kDebugMode) print('Android Auto Album Fetch Error: $e');
          }
        }
        return [];
    }
  }

  // ── Home: Spotify‑style flat card grid ───────────────────
  Future<List<MediaItem>> _buildHomeCards() async {
    final List<MediaItem> cards = [];

    // Time‑of‑day greeting
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    // 1. Recently played tracks as cards
    final prefs = await SharedPreferences.getInstance();
    final recentJson = prefs.getStringList('recently_played') ?? [];
    int addedRecent = 0;
    for (final json in recentJson) {
      if (addedRecent >= 6) break;
      try {
        final track = Track.fromJson(jsonDecode(json));
        // Avoid duplicating the same track
        if (!cards.any((c) => c.id == track.id)) {
          final mi = _trackToMediaItem(track);
          cards.add(mi.copyWith(
            extras: <String, dynamic>{_groupTitleKey: greeting, ...?mi.extras},
          ));
          addedRecent++;
        }
      } catch (_) {}
    }

    // 2. Items from home page shelves — each shelf becomes a titled group
    final homeCache = HiveService.homePageBox.values.firstOrNull;
    if (homeCache != null && homeCache.shelvesJson.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(homeCache.shelvesJson);
        final shelves = jsonList
            .map((e) => HomeShelf.fromJson(e as Map<String, dynamic>))
            .where((s) => s.items.isNotEmpty)
            .toList();

        for (final shelf in shelves) {
          for (final item in shelf.items) {
            final mi = _shelfItemToMediaItem(item);
            if (!cards.any((c) => c.id == mi.id)) {
              cards.add(mi.copyWith(
                extras: <String, dynamic>{_groupTitleKey: shelf.title, ...?mi.extras},
              ));
            }
          }
        }
      } catch (_) {}
    }

    return cards;
  }

  // ── History ──────────────────────────────────────────────
  Future<List<MediaItem>> _buildRecentCards() async {
    final List<MediaItem> items = [];
    try {
      final sections = await _ytMusicService.getHistorySections();
      for (final section in sections) {
        for (final track in section.tracks.take(20)) {
          final mi = _trackToMediaItem(track);
          // Add group title to each item in the section
          if (!items.any((c) => c.id == mi.id)) {
            items.add(mi.copyWith(
              extras: <String, dynamic>{
                _groupTitleKey: section.title,
                ...?mi.extras,
              },
            ));
          }
        }
      }
      if (kDebugMode) print('Android Auto History: Loaded ${items.length} items from YTMusic');
      return items;
    } catch (e) {
      if (kDebugMode) print('Android Auto History Error: $e');
      
      // Fallback to local SharedPreferences if offline or fails
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getStringList('recently_played') ?? [];
      for (final json in recentJson) {
        try {
          final track = Track.fromJson(jsonDecode(json));
          final mi = _trackToMediaItem(track);
          items.add(mi.copyWith(
            extras: <String, dynamic>{
              _groupTitleKey: 'Local History',
              ...?mi.extras,
            },
          ));
        } catch (_) {}
      }
      return items;
    }
  }

  // ── Your Library ─────────────────────────────────────────
  Future<List<MediaItem>> _buildLibraryItems() async {
    final localCount = HiveService.localMusicTracksBox.length;
    
    return [
      const MediaItem(
        id: 'liked_songs',
        title: 'Liked Songs',
        playable: false,
        extras: <String, dynamic>{
          AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
        },
      ),
      const MediaItem(
        id: 'library_playlists',
        title: 'Playlists',
        playable: false,
        extras: <String, dynamic>{
          AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.browsableHintKey: AndroidContentStyle.gridItemHintValue,
        },
      ),
      const MediaItem(
        id: 'library_albums',
        title: 'Albums',
        playable: false,
        extras: <String, dynamic>{
          AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.browsableHintKey: AndroidContentStyle.gridItemHintValue,
        },
      ),
      MediaItem(
        id: 'downloaded',
        title: 'Downloaded',
        playable: false,
        extras: const <String, dynamic>{
          AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
        },
      ),
      MediaItem(
        id: 'local_music',
        title: 'Local Music',
        artist: '$localCount songs',
        playable: false,
        extras: const <String, dynamic>{
          AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
        },
      ),
    ];
  }

  // ── Shelf drill‑down ─────────────────────────────────────
  List<MediaItem> _buildShelfItems(String shelfId) {
    final homeCache = HiveService.homePageBox.values.firstOrNull;
    if (homeCache == null || homeCache.shelvesJson.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(homeCache.shelvesJson);
      final shelves = jsonList
          .map((e) => HomeShelf.fromJson(e as Map<String, dynamic>))
          .toList();
      final shelf = shelves.firstWhere((s) => s.id == shelfId);
      return shelf.items.map(_shelfItemToMediaItem).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Media item lookup ────────────────────────────────────
  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final entity = HiveService.tracksBox.get(mediaId) ??
        HiveService.localMusicTracksBox.get(mediaId);
    if (entity != null) {
      return _trackToMediaItem(_entityToTrack(entity));
    }
    return null;
  }

  // ── Playback from media id ───────────────────────────────
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    Track? trackToPlay;

    // 1. Hive cache
    final entity = HiveService.tracksBox.get(mediaId) ??
        HiveService.localMusicTracksBox.get(mediaId);
    if (entity != null) trackToPlay = _entityToTrack(entity);

    // 2. Recently played
    if (trackToPlay == null) {
      final prefs = await SharedPreferences.getInstance();
      for (final json in prefs.getStringList('recently_played') ?? []) {
        try {
          final t = Track.fromJson(jsonDecode(json));
          if (t.id == mediaId) {
            trackToPlay = t;
            break;
          }
        } catch (_) {}
      }
    }

    // 3. Home shelf items
    if (trackToPlay == null) {
      final homeCache = HiveService.homePageBox.values.firstOrNull;
      if (homeCache != null && homeCache.shelvesJson.isNotEmpty) {
        try {
          final List<dynamic> jsonList = jsonDecode(homeCache.shelvesJson);
          final shelves = jsonList
              .map((e) => HomeShelf.fromJson(e as Map<String, dynamic>))
              .toList();
          for (final shelf in shelves) {
            for (final item in shelf.items) {
              if ((item.videoId == mediaId || item.id == mediaId) &&
                  item.itemType == HomeShelfItemType.song) {
                trackToPlay = item.toTrack();
                break;
              }
            }
            if (trackToPlay != null) break;
          }
        } catch (_) {}
      }
    }

    if (trackToPlay != null) {
      await _playerService.playTrack(trackToPlay);
    }
  }

  // ── Play from voice search ───────────────────────────────
  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    final source = MusicLocalSource();
    final result = await source.searchTracks(query);
    final tracks = result.getOrDefault([]);
    if (tracks.isNotEmpty) {
      await _playerService.playQueue(tracks);
    }
  }

  // ── Search results ───────────────────────────────────────
  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.isEmpty) return [];
    try {
      // Use explicit "songs" filter from search_service.dart
      final result = await _ytMusicService.search(query, filter: 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D');
      final items = result.tracks.take(30).map(_trackToMediaItem).toList();
      
      if (items.isEmpty) {
        return [
          MediaItem(
            id: 'search_empty',
            title: 'No songs found for "$query"',
            artist: 'YT Music returned 0 tracks. Try a different term.',
            playable: false,
          )
        ];
      }
      return items;
    } catch (e) {
      if (kDebugMode) print('Android Auto Search Error: $e');
      return [
        MediaItem(
          id: 'search_error',
          title: 'Search failed',
          artist: e.toString(),
          playable: false,
        )
      ];
    }
  }

  // ── Converters ───────────────────────────────────────────

  MediaItem _trackToMediaItem(Track track) {
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album ?? '',
      duration: track.duration,
      artUri: track.bestThumbnail != null
          ? Uri.parse(track.bestThumbnail!)
          : null,
      playable: true,
    );
  }

  MediaItem _shelfItemToMediaItem(HomeShelfItem item) {
    final bool isPlayable = item.itemType == HomeShelfItemType.song;
    return MediaItem(
      id: item.videoId ?? item.playlistId ?? item.navigationId ?? item.id,
      title: item.title,
      artist: item.subtitle,
      artUri: item.thumbnailUrl != null ? Uri.parse(item.thumbnailUrl!) : null,
      playable: isPlayable,
    );
  }

  Track _entityToTrack(TrackEntity entity) {
    return Track(
      id: entity.id,
      title: entity.title,
      artist: entity.artist,
      album: entity.album,
      duration: Duration(milliseconds: entity.duration),
      thumbnailUrl: entity.thumbnailUrl,
      isExplicit: entity.isExplicit,
      isLiked: entity.isLiked,
      addedAt: entity.addedAt,
      localFilePath: entity.localFilePath,
    );
  }

  void dispose() {
    _stateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _playerService.dispose();
  }
}

/// Initialize audio service with Android Auto grid layout & search support
Future<InzxAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => InzxAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.nirmal.inzx',
      androidNotificationChannelName: 'Inzx Music',
      androidNotificationChannelDescription: 'Music playback controls',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
      fastForwardInterval: const Duration(seconds: 10),
      rewindInterval: const Duration(seconds: 10),
      androidBrowsableRootExtras: <String, dynamic>{
        // Tell Android Auto we support content styling (card grids)
        AndroidContentStyle.supportedKey: true,
        // Default style for root‑level browsable children → grid cards
        AndroidContentStyle.browsableHintKey:
            AndroidContentStyle.gridItemHintValue,
        // Default style for root‑level playable children → grid cards
        AndroidContentStyle.playableHintKey:
            AndroidContentStyle.gridItemHintValue,
        // Enable the search button on Android Auto
        'android.media.browse.SEARCH_SUPPORTED': true,
      },
    ),
  );
}
