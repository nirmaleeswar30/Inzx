import 'package:inzx/core/services/result.dart';
import 'package:inzx/models/track.dart';
import 'package:inzx/services/ytmusic_api_service.dart';
import 'package:inzx/services/youtube_music_service.dart';
import 'package:inzx/services/ytmusic_auth_service.dart';

/// Remote data source wrapping YouTube Music services
class MusicRemoteSource {
  final InnerTubeService _innerTube;
  final YouTubeMusicService _ytMusic;
  final YTMusicAuthService _authService;

  MusicRemoteSource({
    required InnerTubeService innerTube,
    required YouTubeMusicService ytMusic,
    required YTMusicAuthService authService,
  }) : _innerTube = innerTube,
       _ytMusic = ytMusic,
       _authService = authService;

  // ============ Search Operations ============

  /// Search for tracks on YouTube Music
  Future<Result<List<Track>>> searchTracks(String query) async {
    try {
      final results = await _innerTube.search(query);
      return Result.success(results.tracks);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(NetworkException('Failed to search tracks: $e'));
    }
  }

  /// Get trending tracks
  Future<Result<List<Track>>> getTrendingTracks() async {
    try {
      final results = await _ytMusic.getTrendingMusic();
      return Result.success(results);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(
        NetworkException('Failed to get trending tracks: $e'),
      );
    }
  }

  // ============ Library Operations (Auth Required) ============

  /// Get liked songs (requires authentication)
  Future<Result<List<Track>>> getLikedSongs() async {
    try {
      // Check if user is authenticated
      if (!_authService.isLoggedIn) {
        return Result.failure(AuthException('User not authenticated'));
      }

      final songs = await _innerTube.getLikedSongs();
      return Result.success(songs);
    } on AuthException catch (e) {
      return Result.failure(e);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(NetworkException('Failed to get liked songs: $e'));
    }
  }

  /// Get recently played tracks (requires authentication)
  Future<Result<List<Track>>> getRecentlyPlayed() async {
    try {
      if (!_authService.isLoggedIn) {
        return Result.failure(AuthException('User not authenticated'));
      }

      final tracks = await _innerTube.getRecentlyPlayed();
      return Result.success(tracks);
    } on AuthException catch (e) {
      return Result.failure(e);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(
        NetworkException('Failed to get recently played: $e'),
      );
    }
  }

  /// Get all albums (requires authentication)
  Future<Result<List<dynamic>>> getSavedAlbums() async {
    try {
      if (!_authService.isLoggedIn) {
        return Result.failure(AuthException('User not authenticated'));
      }

      final albums = await _innerTube.getSavedAlbums();
      return Result.success(albums);
    } on AuthException catch (e) {
      return Result.failure(e);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(NetworkException('Failed to get saved albums: $e'));
    }
  }

  /// Get all playlists (requires authentication)
  Future<Result<List<dynamic>>> getSavedPlaylists() async {
    try {
      if (!_authService.isLoggedIn) {
        return Result.failure(AuthException('User not authenticated'));
      }

      final playlists = await _innerTube.getSavedPlaylists();
      return Result.success(playlists);
    } on AuthException catch (e) {
      return Result.failure(e);
    } on NetworkException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(
        NetworkException('Failed to get saved playlists: $e'),
      );
    }
  }

  // ============ Utility Methods ============

  /// Check if user is currently authenticated
  bool get isAuthenticated => _authService.isLoggedIn;

  /// Get current user account info (if authenticated)
  // ignore: unnecessary_getters_setters
  get currentAccount => _authService.account;
}
