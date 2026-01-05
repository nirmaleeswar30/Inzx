import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Search history storage keys
const _searchHistoryKey = 'search_history';
const _recentlyPlayedKey = 'recently_played';
const _maxHistoryItems = 20;
const _maxRecentlyPlayed = 50;

/// Search history notifier
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_searchHistoryKey) ?? [];
    state = history;
  }

  Future<void> addSearch(String query) async {
    if (query.trim().isEmpty) return;

    final trimmed = query.trim();
    // Remove if exists, add to front
    final newHistory = [
      trimmed,
      ...state.where((s) => s != trimmed),
    ].take(_maxHistoryItems).toList();

    state = newHistory;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryKey, newHistory);
  }

  Future<void> removeSearch(String query) async {
    final newHistory = state.where((s) => s != query).toList();
    state = newHistory;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryKey, newHistory);
  }

  Future<void> clearHistory() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }
}

/// Recently played tracks notifier
class RecentlyPlayedNotifier extends StateNotifier<List<Track>> {
  RecentlyPlayedNotifier() : super([]) {
    _loadRecentlyPlayed();
  }

  Future<void> _loadRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentlyPlayedKey) ?? [];

    try {
      final tracks = await compute(_parseRecentlyPlayedIsolate, jsonList);
      state = tracks;
    } catch (e) {
      if (kDebugMode) {print('Error loading recently played: $e');}
      state = [];
    }
  }

  Future<void> addTrack(Track track) async {
    // Remove if exists, add to front
    final newList = [
      track,
      ...state.where((t) => t.id != track.id),
    ].take(_maxRecentlyPlayed).toList();

    state = newList;

    final prefs = await SharedPreferences.getInstance();
    final jsonList = await compute(
      _encodeRecentlyPlayedIsolate,
      newList.map((t) => t.toJson()).toList(),
    );
    await prefs.setStringList(_recentlyPlayedKey, jsonList);
  }

  Future<void> removeTrack(String trackId) async {
    final newList = state.where((t) => t.id != trackId).toList();
    state = newList;

    final prefs = await SharedPreferences.getInstance();
    final jsonList = await compute(
      _encodeRecentlyPlayedIsolate,
      newList.map((t) => t.toJson()).toList(),
    );
    await prefs.setStringList(_recentlyPlayedKey, jsonList);
  }

  Future<void> clearHistory() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentlyPlayedKey);
  }
}

/// Provider for search history
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier();
    });

/// Provider for recently played tracks
final recentlyPlayedProvider =
    StateNotifierProvider<RecentlyPlayedNotifier, List<Track>>((ref) {
      return RecentlyPlayedNotifier();
    });

/// Provider for filtered search history (matching current query)
final filteredSearchHistoryProvider = Provider.family<List<String>, String>((
  ref,
  query,
) {
  final history = ref.watch(searchHistoryProvider);
  if (query.isEmpty) return history;

  final lowerQuery = query.toLowerCase();
  return history.where((s) => s.toLowerCase().contains(lowerQuery)).toList();
});

// ============ ISOLATE FUNCTIONS ============

/// Parse recently played tracks from JSON list
List<Track> _parseRecentlyPlayedIsolate(List<String> jsonList) {
  return jsonList.map((json) => Track.fromJson(jsonDecode(json))).toList();
}

/// Encode recently played tracks to JSON list
List<String> _encodeRecentlyPlayedIsolate(List<Map<String, dynamic>> tracks) {
  return tracks.map((t) => jsonEncode(t)).toList();
}
