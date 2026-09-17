import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inzx/core/services/cache/hive_service.dart';
import 'package:inzx/data/entities/lyrics_entity.dart';
import 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;
import 'lyrics_models.dart';
import 'betterlyrics_portato_provider.dart';
import 'betterlyrics_provider.dart';
import 'paxsenix_provider.dart';
import 'binilyrics_provider.dart';
import 'unison_provider.dart';
import 'megalobiz_provider.dart';
import 'lyricsplus_provider.dart';
import 'simpmusic_provider.dart';
import 'musixmatch_provider.dart';
import 'kugou_provider.dart';
import 'lrclib_provider.dart';
import 'youtube_lyrics_provider.dart';
import 'genius_provider.dart';
import 'embedded_lyrics_provider.dart';
import 'instrumental_gaps.dart';

/// Provider names enum for type safety
enum ProviderName {
  betterLyrics,
  betterLyricsPortato,
  paxSenix,
  simpMusic,
  lyricsPlus,
  lrclib,
  unison,
  biniLyrics,
  musixmatch,
  kugou,
  megalobiz,
  youtubeMusic,
  genius,
  embedded,
}

/// All available provider names in priority order
const providerNames = [
  ProviderName.betterLyrics,
  ProviderName.betterLyricsPortato,
  ProviderName.paxSenix,
  ProviderName.simpMusic,
  ProviderName.lyricsPlus,
  ProviderName.lrclib,
  ProviderName.unison,
  ProviderName.biniLyrics,
  ProviderName.musixmatch,
  ProviderName.kugou,
  ProviderName.megalobiz,
  ProviderName.youtubeMusic,
  ProviderName.genius,
  ProviderName.embedded,
];

/// Extension to get display name
extension ProviderNameExt on ProviderName {
  String get displayName {
    switch (this) {
      case ProviderName.biniLyrics:
        return 'BiniLyrics';
      case ProviderName.unison:
        return 'Unison';
      case ProviderName.megalobiz:
        return 'Megalobiz';
      case ProviderName.betterLyrics:
        return 'BetterLyrics';
      case ProviderName.betterLyricsPortato:
        return 'BetterLyrics Portato';
      case ProviderName.paxSenix:
        return 'PaxSenix';
      case ProviderName.lyricsPlus:
        return 'LyricsPlus';
      case ProviderName.simpMusic:
        return 'SimpMusic';
      case ProviderName.musixmatch:
        return 'Musixmatch';
      case ProviderName.kugou:
        return 'KuGou';
      case ProviderName.lrclib:
        return 'LRCLib';
      case ProviderName.youtubeMusic:
        return 'YouTube Music';
      case ProviderName.genius:
        return 'Genius';
      case ProviderName.embedded:
        return 'Embedded';
    }
  }
}

/// Lightweight background lyrics warmup for playback.
/// Queries word-synced & fast-synced providers in parallel with timeout.
class LyricsWarmupService {
  static final LyricsWarmupService instance = LyricsWarmupService._();
  LyricsWarmupService._();

  final BetterLyricsProvider _betterLyrics = BetterLyricsProvider();
  final BetterLyricsPortatoProvider _betterLyricsPortato = BetterLyricsPortatoProvider();
  final PaxSenixProvider _paxSenix = PaxSenixProvider();
  final LyricsPlusProvider _lyricsPlus = LyricsPlusProvider();
  final SimpMusicProvider _simpMusic = SimpMusicProvider();
  final LRCLibProvider _lrclib = LRCLibProvider();
  final GeniusProvider _genius = GeniusProvider();
  final Set<String> _inFlight = <String>{};

  Future<void> prefetchForTrack({
    required String videoId,
    required String title,
    required String artist,
    String? album,
    required int durationSeconds,
    String? localFilePath,
  }) async {
    if (videoId.isEmpty) return;
    if (_inFlight.contains(videoId)) return;
    if (_hasCachedLyrics(videoId)) return;

    _inFlight.add(videoId);
    try {
      final info = LyricsSearchInfo(
        videoId: videoId,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
        localFilePath: localFilePath,
      );

      LyricResult? bestResult;

      // 1. Race word-synced providers with timeout
      final wordSyncFutures = [
        _betterLyrics.search(info),
        _betterLyricsPortato.search(info),
        _paxSenix.search(info),
        _simpMusic.search(info),
        _lyricsPlus.search(info),
      ];

      for (final future in wordSyncFutures) {
        try {
          final res = await future.timeout(
            const Duration(seconds: 4),
            onTimeout: () => null,
          );
          if (res != null && res.hasLyrics) {
            if (res.hasWordSync) {
              bestResult = res;
              break;
            }
            bestResult ??= res;
          }
        } catch (_) {}
      }

      // 2. Fallback to LRCLib if needed
      bestResult ??= await _lrclib.search(info).timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );

      // 3. Fallback to Genius if needed
      bestResult ??= await _genius.search(info).timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );

      if (bestResult == null || !bestResult.hasLyrics) return;

      _cacheLyrics(videoId, title, artist, bestResult);
      if (kDebugMode) {
        print(
          'LyricsService: Warmed lyrics for $videoId using ${bestResult.source}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('LyricsService: Warmup failed for $videoId: $e');
      }
    } finally {
      _inFlight.remove(videoId);
    }
  }

  bool _hasCachedLyrics(String videoId) {
    try {
      final cached = HiveService.lyricsBox.get(videoId);
      return cached != null && !cached.isExpired && cached.hasLyrics;
    } catch (_) {
      return false;
    }
  }

  void _cacheLyrics(
    String videoId,
    String title,
    String artist,
    LyricResult result,
  ) {
    final entity = LyricsEntity(
      trackId: videoId,
      title: title,
      artist: artist,
      syncedLyrics: _linesToLrc(result.lines),
      plainLyrics: result.lyrics,
      provider: result.source,
      cachedAt: DateTime.now(),
      ttlDays: 7,
      wordSyncData: _serializeWordData(result.lines),
    );
    HiveService.lyricsBox.put(videoId, entity);
  }

  /// Serialize word-level timing to JSON for cache storage
  static String? _serializeWordData(List<LyricLine>? lines) {
    if (lines == null || lines.isEmpty) return null;
    final hasAnyWords = lines.any((l) => l.hasWordSync);
    if (!hasAnyWords) return null;
    return jsonEncode(
      lines.map((l) => l.words?.map((w) => w.toJson()).toList()).toList(),
    );
  }

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
  LyricsSearchInfo? _lastSearchInfo;

  LyricsNotifier()
    : _providers = {
        ProviderName.biniLyrics: BiniLyricsProvider(),
        ProviderName.unison: UnisonProvider(),
        ProviderName.megalobiz: MegalobizProvider(),
        ProviderName.betterLyrics: BetterLyricsProvider(),
        ProviderName.betterLyricsPortato: BetterLyricsPortatoProvider(),
        ProviderName.paxSenix: PaxSenixProvider(),
        ProviderName.lyricsPlus: LyricsPlusProvider(),
        ProviderName.simpMusic: SimpMusicProvider(),
        ProviderName.musixmatch: MusixmatchProvider(),
        ProviderName.kugou: KuGouProvider(),
        ProviderName.lrclib: LRCLibProvider(),
        ProviderName.youtubeMusic: YouTubeLyricsProvider(),
        ProviderName.genius: GeniusProvider(),
        ProviderName.embedded: EmbeddedLyricsProvider(),
      },
      super(const LyricsState());

  /// Fetch lyrics for a track from all providers concurrently (with caching and word-sync priority)
  Future<void> fetchLyrics(LyricsSearchInfo info) async {
    _lastSearchInfo = info;

    // Ignore duplicate fetches for the same track while it's already loading.
    if (state.videoId == info.videoId && info.videoId.isNotEmpty) {
      final isAlreadyFetching = state.providers.values.any(
        (s) => s.state == LyricsProviderState.fetching,
      );
      if (isAlreadyFetching) return;
    }

    // Check cache first
    final cached = _getCachedLyrics(info.videoId);
    if (cached != null) {
      final hasSynced =
          cached.lines != null && cached.lines!.any((l) => l.timeInMs > 0);
      // If cached has synced lines, or if duration is not available to improve it, use cache
      if (hasSynced || info.durationSeconds <= 0) {
        CacheAnalytics.instance.recordCacheHit();
        if (kDebugMode) {
          print('LyricsService: Using cached lyrics for ${info.videoId}');
        }
        final cachedProvider =
            _providerNameFromSource(cached.source) ?? ProviderName.betterLyrics;
        final providers = {
          for (final p in providerNames) p: const ProviderStatus(),
        };
        providers[cachedProvider] = ProviderStatus(
          state: LyricsProviderState.done,
          data: cached,
        );
        if (mounted) {
          state = LyricsState(
            videoId: info.videoId,
            providers: providers,
            currentProvider: cachedProvider,
            hasManuallySwitched: false,
          );
        }
        return;
      }
    }

    CacheAnalytics.instance.recordCacheMiss();
    CacheAnalytics.instance.recordNetworkCall();

    // Reset state for new track
    if (mounted) {
      state = LyricsState(
        videoId: info.videoId,
        providers: {
          for (final p in providerNames)
            p: const ProviderStatus(state: LyricsProviderState.idle),
        },
        currentProvider: state.currentProvider,
        hasManuallySwitched: false,
      );
    }

    // 1. If local audio file exists, query embedded/local provider first
    if (info.localFilePath != null && info.localFilePath!.trim().isNotEmpty) {
      await _fetchFromProvider(ProviderName.embedded, info);
      final embStatus = state.providers[ProviderName.embedded];
      if ((embStatus?.data?.hasLyrics ?? false) &&
          embStatus?.state == LyricsProviderState.done) {
        if (!state.hasManuallySwitched) {
          state = state.copyWith(currentProvider: ProviderName.embedded);
        }
        _cacheBestResult(info);
        return;
      }
    }

    // 2. Parallel race all online providers (BitChord architecture)
    final onlineProviders = providerNames.where((p) => p != ProviderName.embedded).toList();

    bool foundWordSync = false;

    await Future.wait(
      onlineProviders.map((providerName) async {
        await _fetchFromProvider(providerName, info);
        if (!mounted) return;

        final status = state.providers[providerName];
        if (status != null && (status.data?.hasWordSync ?? false)) {
          foundWordSync = true;
          if (!state.hasManuallySwitched) {
            final currentBias = _providerBias(state.currentProvider);
            final newBias = _providerBias(providerName);
            if (newBias > currentBias ||
                !(state.currentLyrics?.hasWordSync ?? false)) {
              state = state.copyWith(currentProvider: providerName);
            }
          }
        } else if (!foundWordSync &&
            !state.hasManuallySwitched &&
            (status?.data?.hasSyncedLyrics ?? false)) {
          final currentBias = _providerBias(state.currentProvider);
          final newBias = _providerBias(providerName);
          if (newBias > currentBias) {
            state = state.copyWith(currentProvider: providerName);
          }
        }
      }),
    );

    // Auto-select best provider if not manually switched
    if (!state.hasManuallySwitched) {
      _selectBestProvider();
    }

    // Cache the best result
    _cacheBestResult(info);
  }

  /// Get cached lyrics for a track
  LyricResult? _getCachedLyrics(String videoId) {
    if (videoId.isEmpty) return null;
    try {
      final cached = HiveService.lyricsBox.get(videoId);
      if (cached != null && !cached.isExpired && cached.hasLyrics) {
        // Parse synced lyrics from LRC format back to LyricLine list
        List<LyricLine>? lines;
        if (cached.hasSyncedLyrics) {
          lines = _parseLrcToLines(cached.syncedLyrics!);
          // Restore word-level timing if available
          if (cached.hasWordSync && lines.isNotEmpty) {
            lines = _restoreWordData(lines, cached.wordSyncData!);
          }
          lines = lines.withInstrumentalGaps();
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

  ProviderName? _providerNameFromSource(String? source) {
    if (source == null) return null;
    final normalized = source.trim().toLowerCase();
    if (normalized.contains('embedded') || normalized.contains('local')) {
      return ProviderName.embedded;
    }
    if (normalized.contains('betterlyrics portato')) return ProviderName.betterLyricsPortato;
    if (normalized.contains('betterlyrics')) return ProviderName.betterLyrics;
    if (normalized.contains('paxsenix')) return ProviderName.paxSenix;
    if (normalized.contains('lyricsplus')) return ProviderName.lyricsPlus;
    if (normalized.contains('simpmusic')) return ProviderName.simpMusic;
    if (normalized.contains('musixmatch')) return ProviderName.musixmatch;
    if (normalized.contains('kugou')) return ProviderName.kugou;
    if (normalized.contains('lrclib')) return ProviderName.lrclib;
    if (normalized.contains('youtube')) return ProviderName.youtubeMusic;
    if (normalized.contains('genius')) return ProviderName.genius;
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
          wordSyncData: _serializeWordData(data.lines),
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

  /// Serialize word-level timing to JSON for cache storage
  static String? _serializeWordData(List<LyricLine>? lines) {
    if (lines == null || lines.isEmpty) return null;
    final hasAnyWords = lines.any((l) => l.hasWordSync);
    if (!hasAnyWords) return null;
    return jsonEncode(
      lines.map((l) => l.words?.map((w) => w.toJson()).toList()).toList(),
    );
  }

  /// Restore word-level timing from cached JSON into parsed LyricLines
  static List<LyricLine> _restoreWordData(
    List<LyricLine> lines,
    String wordSyncJson,
  ) {
    try {
      final wordData = jsonDecode(wordSyncJson) as List;
      if (wordData.length != lines.length) return lines;

      return List.generate(lines.length, (i) {
        final lineWords = wordData[i] as List?;
        if (lineWords == null || lineWords.isEmpty) return lines[i];

        return LyricLine(
          timeInMs: lines[i].timeInMs,
          durationMs: lines[i].durationMs,
          text: lines[i].text,
          words: lineWords
              .map((w) => LyricWord.fromJson(w as Map<String, dynamic>))
              .toList(),
        );
      });
    } catch (e) {
      if (kDebugMode) {
        print('LyricsService: Failed to restore word data: $e');
      }
      return lines;
    }
  }

  Future<void> _fetchFromProvider(
    ProviderName name,
    LyricsSearchInfo info,
  ) async {
    if (!mounted) return;
    final currentProviders = Map<ProviderName, ProviderStatus>.from(
      state.providers,
    );
    currentProviders[name] = const ProviderStatus(
      state: LyricsProviderState.fetching,
    );
    state = state.copyWith(providers: currentProviders);

    try {
      final provider = _providers[name]!;
      final result = await provider.search(info);

      if (!mounted) return;
      _updateProviderStatus(
        name,
        ProviderStatus(state: LyricsProviderState.done, data: result),
      );
    } catch (e) {
      if (!mounted) return;
      _updateProviderStatus(
        name,
        ProviderStatus(state: LyricsProviderState.error, error: e.toString()),
      );
    }
  }

  void _updateProviderStatus(ProviderName name, ProviderStatus status) {
    if (!mounted) return;
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
    if (status == null) return -20;

    int bias = 0;

    // Provider status
    if (status.state == LyricsProviderState.done) {
      bias += 1;
    } else if (status.state == LyricsProviderState.fetching) {
      bias -= 1;
    } else if (status.state == LyricsProviderState.error) {
      bias -= 5;
    }

    // Quality bonus
    if (status.data?.hasWordSync ?? false) {
      bias += 25; // Word-level sync wins outright
    } else if (status.data?.hasSyncedLyrics ?? false) {
      bias += 12; // Line-level sync
    } else if (status.data?.hasPlainLyrics ?? false) {
      bias += 3; // Plain text
    } else {
      return -15; // No lyrics
    }

    // Tie-breaker priority ranking
    switch (name) {
      case ProviderName.embedded:
        bias += 9;
        break;
      case ProviderName.betterLyrics:
        bias += 8;
        break;
      case ProviderName.betterLyricsPortato:
        bias += 7;
        break;
      case ProviderName.paxSenix:
        bias += 7;
        break;
      case ProviderName.lyricsPlus:
        bias += 6;
        break;
      case ProviderName.simpMusic:
        bias += 5;
        break;
      case ProviderName.biniLyrics:
      case ProviderName.unison:
        bias += 5;
        break;
      case ProviderName.lrclib:
        bias += 4;
        break;
      case ProviderName.musixmatch:
        bias += 3;
        break;
      case ProviderName.megalobiz:
      case ProviderName.kugou:
        bias += 2;
        break;
      case ProviderName.youtubeMusic:
        bias += 1;
        break;
      case ProviderName.genius:
        bias += 0;
        break;
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

  /// Manually switch to next provider and fetch lyrics if not yet loaded
  Future<void> nextProvider() async {
    final currentIdx = providerNames.indexOf(state.currentProvider);
    final nextIdx = (currentIdx + 1) % providerNames.length;
    final next = providerNames[nextIdx];

    if (mounted) {
      state = state.copyWith(
        currentProvider: next,
        hasManuallySwitched: true,
      );
    }

    final status = state.providers[next];
    final needsFetch =
        status == null ||
        status.state == LyricsProviderState.idle ||
        (status.data == null && status.state != LyricsProviderState.fetching);

    if (needsFetch && _lastSearchInfo != null) {
      await _fetchFromProvider(next, _lastSearchInfo!);
      if (mounted) {
        _cacheBestResult(_lastSearchInfo!);
      }
    }
  }

  /// Manually switch to previous provider and fetch lyrics if not yet loaded
  Future<void> previousProvider() async {
    final currentIdx = providerNames.indexOf(state.currentProvider);
    final prevIdx =
        (currentIdx - 1 + providerNames.length) % providerNames.length;
    final prev = providerNames[prevIdx];

    if (mounted) {
      state = state.copyWith(
        currentProvider: prev,
        hasManuallySwitched: true,
      );
    }

    final status = state.providers[prev];
    final needsFetch =
        status == null ||
        status.state == LyricsProviderState.idle ||
        (status.data == null && status.state != LyricsProviderState.fetching);

    if (needsFetch && _lastSearchInfo != null) {
      await _fetchFromProvider(prev, _lastSearchInfo!);
      if (mounted) {
        _cacheBestResult(_lastSearchInfo!);
      }
    }
  }

  /// Manually switch to a specific provider and fetch lyrics if not yet loaded
  Future<void> selectProvider(ProviderName provider) async {
    if (state.currentProvider == provider) return;

    if (mounted) {
      state = state.copyWith(
        currentProvider: provider,
        hasManuallySwitched: true,
      );
    }

    final status = state.providers[provider];
    final needsFetch =
        status == null ||
        status.state == LyricsProviderState.idle ||
        (status.data == null && status.state != LyricsProviderState.fetching);

    if (needsFetch && _lastSearchInfo != null) {
      await _fetchFromProvider(provider, _lastSearchInfo!);
      if (mounted) {
        _cacheBestResult(_lastSearchInfo!);
      }
    }
  }

  /// Clear lyrics
  void clear() {
    state = const LyricsState();
  }

  /// Update a specific lyric line (e.g. for translation)
  void updateLine(int index, LyricLine updatedLine) {
    if (!mounted) return;
    final currentStatus = state.currentStatus;
    if (currentStatus.state != LyricsProviderState.done || currentStatus.data == null) return;
    
    final currentLines = currentStatus.data!.lines;
    if (currentLines == null || index < 0 || index >= currentLines.length) return;

    final newLines = List<LyricLine>.from(currentLines);
    newLines[index] = updatedLine;

    final newResult = LyricResult(
      title: currentStatus.data!.title,
      artists: currentStatus.data!.artists,
      source: currentStatus.data!.source,
      lines: newLines,
      lyrics: currentStatus.data!.lyrics,
    );

    final newProviders = Map<ProviderName, ProviderStatus>.from(state.providers);
    newProviders[state.currentProvider] = ProviderStatus(
      state: LyricsProviderState.done,
      data: newResult,
    );

    state = state.copyWith(providers: newProviders);
  }

  /// Manually force a refetch for the current track
  Future<void> refetchLyrics() async {
    if (_lastSearchInfo != null) {
      // Clear caching and force fetch
      final info = _lastSearchInfo!;
      state = LyricsState(
        videoId: info.videoId,
        providers: {
          for (final p in providerNames)
            p: const ProviderStatus(state: LyricsProviderState.idle),
        },
        currentProvider: state.currentProvider,
      );
      await fetchLyrics(info);
    }
  }
}

/// Global offset in milliseconds applied to the lyrics sync timeline
final lyricsSyncOffsetProvider = StateProvider<int>((ref) => 0);

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
