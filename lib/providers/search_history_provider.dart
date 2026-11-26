// Re-export recently played provider from music_providers for backward compatibility
export 'music_providers.dart'
    show RecentlyPlayedNotifier, recentlyPlayedProvider;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Search history storage keys
const _searchHistoryKey = 'search_history';
const _maxHistoryItems = 20;

/// Search history notifier
class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _loadHistory();
    return [];
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

/// Provider for search history
final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(SearchHistoryNotifier.new);

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
