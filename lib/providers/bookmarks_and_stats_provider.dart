import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/listening_stats_service.dart';
import '../core/providers/listenable_provider.dart';

/// Storage keys
const _bookmarkedAlbumsKey = 'bookmarked_albums';
const _bookmarkedArtistsKey = 'bookmarked_artists';

/// Bookmarked albums notifier
class BookmarkedAlbumsNotifier extends Notifier<List<Album>> {
  @override
  List<Album> build() {
    _load();
    return [];
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
class BookmarkedArtistsNotifier extends Notifier<List<Artist>> {
  @override
  List<Artist> build() {
    _load();
    return [];
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

/// Providers
final bookmarkedAlbumsProvider =
    NotifierProvider<BookmarkedAlbumsNotifier, List<Album>>(BookmarkedAlbumsNotifier.new);

final bookmarkedArtistsProvider =
    NotifierProvider<BookmarkedArtistsNotifier, List<Artist>>(BookmarkedArtistsNotifier.new);

/// Listening statistics: rebuilds what watches it as listening is recorded.
final listeningStatsProvider = listenableProvider<ListeningStatsService>(
  (ref) => ListeningStatsService.instance,
);

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
