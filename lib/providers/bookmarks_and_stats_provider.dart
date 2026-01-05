import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Storage keys
const _bookmarkedAlbumsKey = 'bookmarked_albums';
const _bookmarkedArtistsKey = 'bookmarked_artists';
const _playStatsKey = 'play_statistics';

/// Bookmarked albums notifier
class BookmarkedAlbumsNotifier extends StateNotifier<List<Album>> {
  BookmarkedAlbumsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_bookmarkedAlbumsKey) ?? [];
    try {
      state = await compute(_parseAlbumListIsolate, jsonList);
    } catch (_) {
      state = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = await compute(
      _encodeAlbumListIsolate,
      state.map((a) => a.toJson()).toList(),
    );
    await prefs.setStringList(_bookmarkedAlbumsKey, jsonList);
  }

  void toggleBookmark(Album album) {
    final isBookmarked = state.any((a) => a.id == album.id);
    if (isBookmarked) {
      state = state.where((a) => a.id != album.id).toList();
    } else {
      state = [album, ...state];
    }
    _save();
  }

  bool isBookmarked(String albumId) {
    return state.any((a) => a.id == albumId);
  }
}

/// Bookmarked artists notifier
class BookmarkedArtistsNotifier extends StateNotifier<List<Artist>> {
  BookmarkedArtistsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_bookmarkedArtistsKey) ?? [];
    try {
      state = await compute(_parseArtistListIsolate, jsonList);
    } catch (_) {
      state = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = await compute(
      _encodeArtistListIsolate,
      state.map((a) => a.toJson()).toList(),
    );
    await prefs.setStringList(_bookmarkedArtistsKey, jsonList);
  }

  void toggleBookmark(Artist artist) {
    final isBookmarked = state.any((a) => a.id == artist.id);
    if (isBookmarked) {
      state = state.where((a) => a.id != artist.id).toList();
    } else {
      state = [artist, ...state];
    }
    _save();
  }

  bool isBookmarked(String artistId) {
    return state.any((a) => a.id == artistId);
  }
}

/// Play statistics for a track
class TrackPlayStats {
  final String trackId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int playCount;
  final Duration totalPlayTime;
  final DateTime lastPlayed;

  const TrackPlayStats({
    required this.trackId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.playCount,
    required this.totalPlayTime,
    required this.lastPlayed,
  });

  TrackPlayStats copyWith({
    int? playCount,
    Duration? totalPlayTime,
    DateTime? lastPlayed,
  }) => TrackPlayStats(
    trackId: trackId,
    title: title,
    artist: artist,
    thumbnailUrl: thumbnailUrl,
    playCount: playCount ?? this.playCount,
    totalPlayTime: totalPlayTime ?? this.totalPlayTime,
    lastPlayed: lastPlayed ?? this.lastPlayed,
  );

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'playCount': playCount,
    'totalPlayTimeMs': totalPlayTime.inMilliseconds,
    'lastPlayed': lastPlayed.toIso8601String(),
  };

  factory TrackPlayStats.fromJson(Map<String, dynamic> json) => TrackPlayStats(
    trackId: json['trackId'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    playCount: json['playCount'] as int,
    totalPlayTime: Duration(milliseconds: json['totalPlayTimeMs'] as int),
    lastPlayed: DateTime.parse(json['lastPlayed'] as String),
  );
}

/// Play statistics notifier
class PlayStatisticsNotifier
    extends StateNotifier<Map<String, TrackPlayStats>> {
  PlayStatisticsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_playStatsKey);
    if (json == null) return;

    try {
      state = await compute(_parsePlayStatsIsolate, json);
    } catch (_) {
      state = {};
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final dataToEncode = state.map((k, v) => MapEntry(k, v.toJson()));
    final json = await compute(_encodePlayStatsIsolate, dataToEncode);
    await prefs.setString(_playStatsKey, json);
  }

  /// Record a play for a track
  void recordPlay(Track track, {Duration playedDuration = Duration.zero}) {
    final existing = state[track.id];

    if (existing != null) {
      state = {
        ...state,
        track.id: existing.copyWith(
          playCount: existing.playCount + 1,
          totalPlayTime: existing.totalPlayTime + playedDuration,
          lastPlayed: DateTime.now(),
        ),
      };
    } else {
      state = {
        ...state,
        track.id: TrackPlayStats(
          trackId: track.id,
          title: track.title,
          artist: track.artist,
          thumbnailUrl: track.thumbnailUrl,
          playCount: 1,
          totalPlayTime: playedDuration,
          lastPlayed: DateTime.now(),
        ),
      };
    }
    _save();
  }

  /// Get most played tracks
  List<TrackPlayStats> getMostPlayed({int limit = 20}) {
    final sorted = state.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return sorted.take(limit).toList();
  }

  /// Get recently played (different from history - this is stats-based)
  List<TrackPlayStats> getRecentlyPlayed({int limit = 20}) {
    final sorted = state.values.toList()
      ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return sorted.take(limit).toList();
  }

  /// Get total listen time
  Duration get totalListenTime {
    return state.values.fold(
      Duration.zero,
      (sum, stats) => sum + stats.totalPlayTime,
    );
  }

  /// Get total play count
  int get totalPlayCount {
    return state.values.fold(0, (sum, stats) => sum + stats.playCount);
  }

  /// Clear all statistics
  Future<void> clear() async {
    state = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playStatsKey);
  }
}

/// Providers
final bookmarkedAlbumsProvider =
    StateNotifierProvider<BookmarkedAlbumsNotifier, List<Album>>((ref) {
      return BookmarkedAlbumsNotifier();
    });

final bookmarkedArtistsProvider =
    StateNotifierProvider<BookmarkedArtistsNotifier, List<Artist>>((ref) {
      return BookmarkedArtistsNotifier();
    });

final playStatisticsProvider =
    StateNotifierProvider<PlayStatisticsNotifier, Map<String, TrackPlayStats>>((
      ref,
    ) {
      return PlayStatisticsNotifier();
    });

/// Check if album is bookmarked
final isAlbumBookmarkedProvider = Provider.family<bool, String>((ref, albumId) {
  final albums = ref.watch(bookmarkedAlbumsProvider);
  return albums.any((a) => a.id == albumId);
});

/// Check if artist is bookmarked
final isArtistBookmarkedProvider = Provider.family<bool, String>((
  ref,
  artistId,
) {
  final artists = ref.watch(bookmarkedArtistsProvider);
  return artists.any((a) => a.id == artistId);
});

/// Most played tracks provider
final mostPlayedTracksProvider = Provider<List<TrackPlayStats>>((ref) {
  final stats = ref.watch(playStatisticsProvider);
  final sorted = stats.values.toList()
    ..sort((a, b) => b.playCount.compareTo(a.playCount));
  return sorted.take(20).toList();
});

// ============ ISOLATE FUNCTIONS ============

/// Parse list of album JSON strings
List<Album> _parseAlbumListIsolate(List<String> jsonList) {
  return jsonList.map((j) => Album.fromJson(jsonDecode(j))).toList();
}

/// Encode list of albums to JSON strings
List<String> _encodeAlbumListIsolate(List<Map<String, dynamic>> albums) {
  return albums.map((a) => jsonEncode(a)).toList();
}

/// Parse list of artist JSON strings
List<Artist> _parseArtistListIsolate(List<String> jsonList) {
  return jsonList.map((j) => Artist.fromJson(jsonDecode(j))).toList();
}

/// Encode list of artists to JSON strings
List<String> _encodeArtistListIsolate(List<Map<String, dynamic>> artists) {
  return artists.map((a) => jsonEncode(a)).toList();
}

/// Parse play statistics JSON
Map<String, TrackPlayStats> _parsePlayStatsIsolate(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  return map.map((k, v) => MapEntry(k, TrackPlayStats.fromJson(v)));
}

/// Encode play statistics to JSON
String _encodePlayStatsIsolate(Map<String, Map<String, dynamic>> data) {
  return jsonEncode(data);
}
