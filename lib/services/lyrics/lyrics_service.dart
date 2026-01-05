import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inzx/core/services/cache/hive_service.dart';
import 'package:inzx/data/entities/lyrics_entity.dart';
import 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;
import 'lyrics_models.dart';
import 'lrclib_provider.dart';
import 'genius_provider.dart';

/// Provider names enum for type safety
enum ProviderName { lrclib, genius }

/// All available provider names in order
const providerNames = [ProviderName.lrclib, ProviderName.genius];

/// Extension to get display name
extension ProviderNameExt on ProviderName {
  String get displayName {
    switch (this) {
      case ProviderName.lrclib:
        return 'LRCLib';
      case ProviderName.genius:
        return 'Genius';
    }
  }
}

/// Lyrics state for a track
class LyricsState {
  final String? videoId;
  final Map<ProviderName, ProviderStatus> providers;
  final ProviderName currentProvider;
  final bool hasManuallySwitched;

  const LyricsState({
    this.videoId,
    this.providers = const {},
    this.currentProvider = ProviderName.lrclib,
    this.hasManuallySwitched = false,
  });

  ProviderStatus get currentStatus =>
      providers[currentProvider] ?? const ProviderStatus();

  LyricResult? get currentLyrics => currentStatus.data;

  bool get isLoading => currentStatus.state == LyricsProviderState.fetching;

  bool get hasLyrics => currentLyrics?.hasLyrics ?? false;

  LyricsState copyWith({
    String? videoId,
    Map<ProviderName, ProviderStatus>? providers,
    ProviderName? currentProvider,
    bool? hasManuallySwitched,
  }) => LyricsState(
    videoId: videoId ?? this.videoId,
    providers: providers ?? this.providers,
    currentProvider: currentProvider ?? this.currentProvider,
    hasManuallySwitched: hasManuallySwitched ?? this.hasManuallySwitched,
  );
}

/// Lyrics service notifier with caching
class LyricsNotifier extends StateNotifier<LyricsState> {
  final Map<ProviderName, LyricsProvider> _providers;

  LyricsNotifier()
    : _providers = {
        ProviderName.lrclib: LRCLibProvider(),
        ProviderName.genius: GeniusProvider(),
      },
      super(const LyricsState());

  /// Fetch lyrics for a track from all providers (with caching)
  Future<void> fetchLyrics(LyricsSearchInfo info) async {
    // Check cache first
    final cached = _getCachedLyrics(info.videoId);
    if (cached != null) {
      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {
        print('LyricsService: Using cached lyrics for ${info.videoId}');
      }
      state = LyricsState(
        videoId: info.videoId,
        providers: {
          ProviderName.lrclib: ProviderStatus(
            state: LyricsProviderState.done,
            data: cached,
          ),
        },
        currentProvider: ProviderName.lrclib,
        hasManuallySwitched: false,
      );
      return;
    }

    CacheAnalytics.instance.recordCacheMiss();
    CacheAnalytics.instance.recordNetworkCall();
    // Reset state for new track
    state = LyricsState(
      videoId: info.videoId,
      providers: {
        for (final p in providerNames)
          p: const ProviderStatus(state: LyricsProviderState.fetching),
      },
      currentProvider: state.currentProvider,
      hasManuallySwitched: false,
    );

    // Fetch from all providers in parallel
    await Future.wait(providerNames.map((p) => _fetchFromProvider(p, info)));

    // Auto-select best provider if not manually switched
    if (!state.hasManuallySwitched) {
      _selectBestProvider();
    }

    // Cache the best result
    _cacheBestResult(info);
  }

  /// Get cached lyrics for a track
  LyricResult? _getCachedLyrics(String videoId) {
    try {
      final cached = HiveService.lyricsBox.get(videoId);
      if (cached != null && !cached.isExpired && cached.hasLyrics) {
        // Parse synced lyrics from LRC format back to LyricLine list
        List<LyricLine>? lines;
        if (cached.hasSyncedLyrics) {
          lines = _parseLrcToLines(cached.syncedLyrics!);
        }
        return LyricResult(
          title: cached.title,
          artists: [cached.artist],
          lines: lines,
          lyrics: cached.plainLyrics,
          source: cached.provider,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('LyricsService: Cache read error: $e');
      }
    }
    return null;
  }

  /// Parse LRC format string to list of LyricLines
  List<LyricLine> _parseLrcToLines(String lrc) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millis = int.parse(match.group(3)!.padRight(3, '0'));
        final text = match.group(4) ?? '';
        final timeInMs = minutes * 60000 + seconds * 1000 + millis;
        lines.add(LyricLine(timeInMs: timeInMs, text: text));
      }
    }
    return lines;
  }

  /// Convert LyricLines to LRC format string for caching
  String? _linesToLrc(List<LyricLine>? lines) {
    if (lines == null || lines.isEmpty) return null;
    final buffer = StringBuffer();
    for (final line in lines) {
      final minutes = (line.timeInMs ~/ 60000).toString().padLeft(2, '0');
      final seconds = ((line.timeInMs % 60000) ~/ 1000).toString().padLeft(
        2,
        '0',
      );
      final millis = ((line.timeInMs % 1000) ~/ 10).toString().padLeft(2, '0');
      buffer.writeln('[$minutes:$seconds.$millis]${line.text}');
    }
    return buffer.toString();
  }

  /// Cache the best lyrics result
  void _cacheBestResult(LyricsSearchInfo info) {
    try {
      final bestStatus = state.currentStatus;
      if (bestStatus.state == LyricsProviderState.done &&
          bestStatus.data != null &&
          bestStatus.data!.hasLyrics) {
        final data = bestStatus.data!;
        final entity = LyricsEntity(
          trackId: info.videoId,
          title: info.title,
          artist: info.artist,
          syncedLyrics: _linesToLrc(data.lines),
          plainLyrics: data.lyrics,
          provider: data.source,
          cachedAt: DateTime.now(),
          ttlDays: 7,
        );
        HiveService.lyricsBox.put(info.videoId, entity);
        if (kDebugMode) {
          print('LyricsService: Cached lyrics for ${info.videoId}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('LyricsService: Cache write error: $e');
      }
    }
  }

  Future<void> _fetchFromProvider(
    ProviderName name,
    LyricsSearchInfo info,
  ) async {
    try {
      final provider = _providers[name]!;
      final result = await provider.search(info);

      _updateProviderStatus(
        name,
        ProviderStatus(state: LyricsProviderState.done, data: result),
      );
    } catch (e) {
      _updateProviderStatus(
        name,
        ProviderStatus(state: LyricsProviderState.error, error: e.toString()),
      );
    }
  }

  void _updateProviderStatus(ProviderName name, ProviderStatus status) {
    final newProviders = Map<ProviderName, ProviderStatus>.from(
      state.providers,
    );
    newProviders[name] = status;
    state = state.copyWith(providers: newProviders);

    // Auto-select if better provider available
    if (!state.hasManuallySwitched) {
      _selectBestProvider();
    }
  }

  /// Calculate provider bias/score (higher is better)
  int _providerBias(ProviderName name) {
    final status = state.providers[name];
    if (status == null) return -10;

    int bias = 0;

    // Provider is done loading
    if (status.state == LyricsProviderState.done)
      bias += 1;
    else if (status.state == LyricsProviderState.fetching)
      bias -= 1;
    else if (status.state == LyricsProviderState.error)
      bias -= 2;

    // Has synced lyrics (most valuable)
    if (status.data?.hasSyncedLyrics ?? false) bias += 3;

    // Has plain lyrics
    if (status.data?.hasPlainLyrics ?? false) bias += 1;

    // Prefer LRCLib for synced lyrics
    if (name == ProviderName.lrclib &&
        (status.data?.hasSyncedLyrics ?? false)) {
      bias += 1;
    }

    return bias;
  }

  /// Select the best provider based on bias
  void _selectBestProvider() {
    final sorted = List<ProviderName>.from(providerNames);
    sorted.sort((a, b) => _providerBias(b).compareTo(_providerBias(a)));

    final best = sorted.first;

    // Only switch if better than current
    if (_providerBias(best) > _providerBias(state.currentProvider)) {
      state = state.copyWith(currentProvider: best);
    }
  }

  /// Manually switch to next provider
  void nextProvider() {
    final currentIdx = providerNames.indexOf(state.currentProvider);
    final nextIdx = (currentIdx + 1) % providerNames.length;
    state = state.copyWith(
      currentProvider: providerNames[nextIdx],
      hasManuallySwitched: true,
    );
  }

  /// Manually switch to previous provider
  void previousProvider() {
    final currentIdx = providerNames.indexOf(state.currentProvider);
    final prevIdx =
        (currentIdx - 1 + providerNames.length) % providerNames.length;
    state = state.copyWith(
      currentProvider: providerNames[prevIdx],
      hasManuallySwitched: true,
    );
  }

  /// Clear lyrics
  void clear() {
    state = const LyricsState();
  }
}

/// Provider for lyrics service
final lyricsProvider = StateNotifierProvider<LyricsNotifier, LyricsState>((
  ref,
) {
  return LyricsNotifier();
});

/// Provider for current lyric line based on playback position
final currentLyricLineProvider = Provider<LyricLine?>((ref) {
  // Watch lyrics state to trigger rebuilds when lyrics change
  ref.watch(lyricsProvider);
  // This would need to be hooked up to position stream
  // For now returns null - will be connected in UI
  return null;
});
