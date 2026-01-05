import 'package:hive_flutter/hive_flutter.dart';
import 'package:inzx/data/entities/cache_metadata_entity.dart';
import 'package:inzx/data/entities/download_entity.dart';
import 'package:inzx/data/entities/playback_entity.dart';
import 'package:inzx/data/entities/track_entity.dart';
import 'package:inzx/data/entities/lyrics_entity.dart';
import 'package:inzx/data/entities/home_shelf_entity.dart';
import 'package:inzx/data/entities/album_cache_entity.dart';
import 'package:inzx/data/entities/artist_cache_entity.dart';
import 'package:inzx/data/entities/playlist_cache_entity.dart';
import 'package:inzx/data/entities/color_cache_entity.dart';
import 'package:inzx/data/entities/stream_cache_entity.dart';

class HiveService {
  static const String _tracksBoxName = 'music_tracks';
  static const String _searchCacheBoxName = 'music_search_cache';
  static const String _playbackBoxName = 'music_playback';
  static const String _metadataBoxName = 'cache_metadata';
  static const String _downloadsBoxName = 'music_downloads';
  static const String _lyricsBoxName = 'music_lyrics';
  static const String _homePageBoxName = 'home_page_cache';
  static const String _albumsBoxName = 'albums_cache';
  static const String _artistsBoxName = 'artists_cache';
  static const String _playlistsBoxName = 'playlists_cache';
  static const String _colorsBoxName = 'colors_cache';
  static const String _streamCacheBoxName = 'stream_url_cache';

  static late Box<TrackEntity> _tracksBox;
  static late Box<dynamic> _searchCacheBox;
  static late Box<PlaybackEntity> _playbackBox;
  static late Box<CacheMetadataEntity> _metadataBox;
  static late Box<DownloadEntity> _downloadsBox;
  static late Box<LyricsEntity> _lyricsBox;
  static late Box<HomePageCacheEntity> _homePageBox;
  static late Box<AlbumCacheEntity> _albumsBox;
  static late Box<ArtistCacheEntity> _artistsBox;
  static late Box<PlaylistCacheEntity> _playlistsBox;
  static late Box<ColorCacheEntity> _colorsBox;
  static late Box<StreamCacheEntity> _streamCacheBox;

  /// Initialize Hive and all boxes
  static Future<void> init() async {
    // Initialize Hive with Flutter support
    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TrackEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PlaybackEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(CacheMetadataEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(DownloadEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(LyricsEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(HomePageCacheEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(AlbumCacheEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(ArtistCacheEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(PlaylistCacheEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(ColorCacheEntityAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(StreamCacheEntityAdapter());
    }

    // Open boxes
    _tracksBox = await Hive.openBox<TrackEntity>(_tracksBoxName);
    _searchCacheBox = await Hive.openBox(_searchCacheBoxName);
    _playbackBox = await Hive.openBox<PlaybackEntity>(_playbackBoxName);
    _metadataBox = await Hive.openBox<CacheMetadataEntity>(_metadataBoxName);
    _downloadsBox = await Hive.openBox<DownloadEntity>(_downloadsBoxName);
    _lyricsBox = await Hive.openBox<LyricsEntity>(_lyricsBoxName);
    _homePageBox = await Hive.openBox<HomePageCacheEntity>(_homePageBoxName);
    _albumsBox = await Hive.openBox<AlbumCacheEntity>(_albumsBoxName);
    _artistsBox = await Hive.openBox<ArtistCacheEntity>(_artistsBoxName);
    _playlistsBox = await Hive.openBox<PlaylistCacheEntity>(_playlistsBoxName);
    _colorsBox = await Hive.openBox<ColorCacheEntity>(_colorsBoxName);
    _streamCacheBox = await Hive.openBox<StreamCacheEntity>(
      _streamCacheBoxName,
    );

    // Clean up expired cache entries on init
    _cleanupExpiredEntries();
  }

  /// Clean up expired cache entries
  static Future<void> _cleanupExpiredEntries() async {
    final expiredKeys = <String>[];
    for (final entry in _metadataBox.values) {
      if (entry.isExpired()) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      await _searchCacheBox.delete(key);
      await _metadataBox.delete(key);
    }

    // Clean up expired lyrics
    final expiredLyrics = <String>[];
    for (final entry in _lyricsBox.values) {
      if (entry.isExpired) {
        expiredLyrics.add(entry.trackId);
      }
    }
    for (final key in expiredLyrics) {
      await _lyricsBox.delete(key);
    }

    // Clean up expired albums
    final expiredAlbums = <String>[];
    for (final entry in _albumsBox.values) {
      if (entry.isExpired) {
        expiredAlbums.add(entry.albumId);
      }
    }
    for (final key in expiredAlbums) {
      await _albumsBox.delete(key);
    }

    // Clean up expired artists
    final expiredArtists = <String>[];
    for (final entry in _artistsBox.values) {
      if (entry.isExpired) {
        expiredArtists.add(entry.artistId);
      }
    }
    for (final key in expiredArtists) {
      await _artistsBox.delete(key);
    }

    // Clean up expired playlists
    final expiredPlaylists = <String>[];
    for (final entry in _playlistsBox.values) {
      if (entry.isExpired) {
        expiredPlaylists.add(entry.playlistId);
      }
    }
    for (final key in expiredPlaylists) {
      await _playlistsBox.delete(key);
    }
  }

  // ============ Getters ============
  static Box<TrackEntity> get tracksBox => _tracksBox;
  static Box<dynamic> get searchCacheBox => _searchCacheBox;
  static Box<PlaybackEntity> get playbackBox => _playbackBox;
  static Box<CacheMetadataEntity> get metadataBox => _metadataBox;
  static Box<DownloadEntity> get downloadsBox => _downloadsBox;
  static Box<LyricsEntity> get lyricsBox => _lyricsBox;
  static Box<HomePageCacheEntity> get homePageBox => _homePageBox;
  static Box<AlbumCacheEntity> get albumsBox => _albumsBox;
  static Box<ArtistCacheEntity> get artistsBox => _artistsBox;
  static Box<PlaylistCacheEntity> get playlistsBox => _playlistsBox;
  static Box<ColorCacheEntity> get colorsBox => _colorsBox;
  static Box<StreamCacheEntity> get streamCacheBox => _streamCacheBox;

  // ============ Cleanup ============
  static Future<void> closeAllBoxes() async {
    await Hive.close();
  }

  static Future<void> clearAllBoxes() async {
    await _tracksBox.clear();
    await _searchCacheBox.clear();
    await _playbackBox.clear();
    await _metadataBox.clear();
    await _downloadsBox.clear();
    await _lyricsBox.clear();
    await _homePageBox.clear();
    await _albumsBox.clear();
    await _artistsBox.clear();
    await _playlistsBox.clear();
    await _colorsBox.clear();
    await _streamCacheBox.clear();
  }
}
