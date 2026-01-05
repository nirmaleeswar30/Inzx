import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';
import 'ytmusic_api_service.dart';

/// Service to sync YouTube Music library data locally for offline access
class YTMusicSyncService {
  static const String _likedSongsKey = 'ytmusic_liked_songs';
  static const String _savedAlbumsKey = 'ytmusic_saved_albums';
  static const String _savedPlaylistsKey = 'ytmusic_saved_playlists';
  static const String _subscribedArtistsKey = 'ytmusic_subscribed_artists';
  static const String _lastSyncKey = 'ytmusic_last_sync';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final InnerTubeService _innerTube;

  // Cached data
  List<Track>? _likedSongs;
  List<Album>? _savedAlbums;
  List<Playlist>? _savedPlaylists;
  List<Artist>? _subscribedArtists;
  DateTime? _lastSync;

  YTMusicSyncService(this._innerTube);

  /// Get last sync time
  DateTime? get lastSync => _lastSync;

  /// Sync all library data from YouTube Music
  Future<SyncResult> syncAll() async {
    if (!_innerTube.isAuthenticated) {
      return SyncResult(success: false, error: 'Not authenticated');
    }

    int totalSynced = 0;

    try {
      // Sync liked songs
      final likedSongs = await _innerTube.getLikedSongs();
      if (likedSongs.isNotEmpty) {
        _likedSongs = likedSongs;
        await _saveLikedSongs(likedSongs);
        totalSynced += likedSongs.length;
      }

      // Sync saved albums
      final savedAlbums = await _innerTube.getSavedAlbums();
      if (savedAlbums.isNotEmpty) {
        _savedAlbums = savedAlbums;
        await _saveAlbums(savedAlbums);
        totalSynced += savedAlbums.length;
      }

      // Sync saved playlists
      final savedPlaylists = await _innerTube.getSavedPlaylists();
      if (savedPlaylists.isNotEmpty) {
        _savedPlaylists = savedPlaylists;
        await _savePlaylists(savedPlaylists);
        totalSynced += savedPlaylists.length;
      }

      // Sync subscribed artists
      final subscribedArtists = await _innerTube.getSubscribedArtists();
      if (subscribedArtists.isNotEmpty) {
        _subscribedArtists = subscribedArtists;
        await _saveArtists(subscribedArtists);
        totalSynced += subscribedArtists.length;
      }

      // Update last sync time
      _lastSync = DateTime.now();
      await _storage.write(
        key: _lastSyncKey,
        value: _lastSync!.toIso8601String(),
      );

      return SyncResult(
        success: true,
        itemsSynced: totalSynced,
        likedSongs: likedSongs.length,
        savedAlbums: savedAlbums.length,
        savedPlaylists: savedPlaylists.length,
        subscribedArtists: subscribedArtists.length,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Load cached data from storage
  /// JSON parsing runs in background isolate to avoid UI jank
  Future<void> loadCachedData() async {
    try {
      // Load liked songs
      final likedSongsJson = await _storage.read(key: _likedSongsKey);
      if (likedSongsJson != null) {
        _likedSongs = await compute(_parseTrackListIsolate, likedSongsJson);
      }

      // Load saved albums
      final savedAlbumsJson = await _storage.read(key: _savedAlbumsKey);
      if (savedAlbumsJson != null) {
        _savedAlbums = await compute(_parseAlbumListIsolate, savedAlbumsJson);
      }

      // Load saved playlists
      final savedPlaylistsJson = await _storage.read(key: _savedPlaylistsKey);
      if (savedPlaylistsJson != null) {
        _savedPlaylists = await compute(
          _parsePlaylistListIsolate,
          savedPlaylistsJson,
        );
      }

      // Load subscribed artists
      final subscribedArtistsJson = await _storage.read(
        key: _subscribedArtistsKey,
      );
      if (subscribedArtistsJson != null) {
        _subscribedArtists = await compute(
          _parseArtistListIsolate,
          subscribedArtistsJson,
        );
      }

      // Load last sync time
      final lastSyncStr = await _storage.read(key: _lastSyncKey);
      if (lastSyncStr != null) {
        _lastSync = DateTime.parse(lastSyncStr);
      }
    } catch (e) {
      if (kDebugMode) {print('Error loading cached YTMusic data: $e');}
    }
  }

  /// Get cached liked songs
  List<Track> getCachedLikedSongs() => _likedSongs ?? [];

  /// Get cached saved albums
  List<Album> getCachedSavedAlbums() => _savedAlbums ?? [];

  /// Get cached saved playlists
  List<Playlist> getCachedSavedPlaylists() => _savedPlaylists ?? [];

  /// Get cached subscribed artists
  List<Artist> getCachedSubscribedArtists() => _subscribedArtists ?? [];

  /// Clear all cached data
  Future<void> clearCache() async {
    _likedSongs = null;
    _savedAlbums = null;
    _savedPlaylists = null;
    _subscribedArtists = null;
    _lastSync = null;

    await _storage.delete(key: _likedSongsKey);
    await _storage.delete(key: _savedAlbumsKey);
    await _storage.delete(key: _savedPlaylistsKey);
    await _storage.delete(key: _subscribedArtistsKey);
    await _storage.delete(key: _lastSyncKey);
  }

  // Private save methods
  Future<void> _saveLikedSongs(List<Track> tracks) async {
    await _storage.write(
      key: _likedSongsKey,
      value: jsonEncode(tracks.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> _saveAlbums(List<Album> albums) async {
    await _storage.write(
      key: _savedAlbumsKey,
      value: jsonEncode(albums.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> _savePlaylists(List<Playlist> playlists) async {
    await _storage.write(
      key: _savedPlaylistsKey,
      value: jsonEncode(playlists.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _saveArtists(List<Artist> artists) async {
    await _storage.write(
      key: _subscribedArtistsKey,
      value: jsonEncode(artists.map((a) => a.toJson()).toList()),
    );
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String? error;
  final int itemsSynced;
  final int likedSongs;
  final int savedAlbums;
  final int savedPlaylists;
  final int subscribedArtists;

  SyncResult({
    required this.success,
    this.error,
    this.itemsSynced = 0,
    this.likedSongs = 0,
    this.savedAlbums = 0,
    this.savedPlaylists = 0,
    this.subscribedArtists = 0,
  });
}

/// Top-level isolate functions for JSON parsing
List<Track> _parseTrackListIsolate(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
}

List<Album> _parseAlbumListIsolate(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
}

List<Playlist> _parsePlaylistListIsolate(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
}

List<Artist> _parseArtistListIsolate(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Artist.fromJson(e as Map<String, dynamic>)).toList();
}
