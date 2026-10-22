import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../core/services/cache/hive_service.dart';
import '../data/entities/download_entity.dart';
import '../data/entities/downloaded_playlist_entity.dart';
import 'playback/yt_player_utils.dart';
import 'playback/playback_data.dart';
import 'notification_service.dart';
import 'jiosaavn/jiosaavn_service.dart';
import 'audio_player_service.dart' show kJioSaavnEnabledKey;
import 'tagger/media_tagger.dart';
import 'lyrics/lyrics_models.dart';
import 'lyrics/lrclib_provider.dart';
import 'lyrics/betterlyrics_provider.dart';
import 'lyrics/paxsenix_provider.dart';
import 'lyrics/lyricsplus_provider.dart';
import 'lyrics/simpmusic_provider.dart';
import 'lyrics/lrc_writer.dart';

const String kDownloadQualityKey = 'download_quality';
const String kDownloadParallelPartCountKey = 'download_parallel_part_count';
const String kDownloadParallelMinSizeMbKey = 'download_parallel_min_size_mb';
const String kCustomDownloadPathKey = 'custom_download_path';
const int kDefaultParallelDownloadPartCount = 4;
const int kMinParallelDownloadPartCount = 2;
const int kMaxParallelDownloadPartCount = 8;
const int kDefaultParallelDownloadMinSizeMb = 1;
const int kMinParallelDownloadMinSizeMb = 1;
const int kMaxParallelDownloadMinSizeMb = 32;
const int kMaxTransientDownloadRetries = 8;

/// Public accessor for the resolved downloads directory. Used by backup/restore
/// to place audio files extracted from a `.zip` backup.
Future<String> resolveDownloadsDirPath() => _getDownloadsDirPath();

/// Get downloads directory path - checks custom path first, then app-private storage
Future<String> _getDownloadsDirPath() async {
  // 1. Check custom path selected by user
  try {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(kCustomDownloadPathKey);
    if (customPath != null && customPath.trim().isNotEmpty) {
      final customDir = Directory(customPath.trim());
      if (await customDir.exists()) {
        return customDir.path;
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('DownloadService: Error reading custom download path: $e');
    }
  }

  // 2. Use app-private external storage (OuterTune style)
  // Path: /Android/data/<package>/files/audio/
  try {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      final downloadsDir = Directory('${externalDir.path}/audio');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      return downloadsDir.path;
    }
  } catch (e) {
    if (kDebugMode) {
      print('DownloadService: Cannot use external storage: $e');
    }
  }

  // 3. Ultimate fallback: app documents directory
  final appDir = await getApplicationDocumentsDirectory();
  final downloadsDir = Directory('${appDir.path}/audio');
  if (!await downloadsDir.exists()) {
    await downloadsDir.create(recursive: true);
  }
  return downloadsDir.path;
}

/// Information about current download path and whether it is a user-chosen custom path
class DownloadPathInfo {
  final String path;
  final bool isCustom;
  const DownloadPathInfo({required this.path, required this.isCustom});
}

/// State notifier for download path allowing custom path selection
class DownloadPathNotifier extends StateNotifier<AsyncValue<DownloadPathInfo>> {
  DownloadPathNotifier() : super(const AsyncValue.loading()) {
    loadPath();
  }

  Future<void> loadPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(kCustomDownloadPathKey);
      final hasCustom = custom != null && custom.trim().isNotEmpty;
      final path = await _getDownloadsDirPath();
      state = AsyncValue.data(DownloadPathInfo(path: path, isCustom: hasCustom));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> setCustomPath(String? path) async {
    state = const AsyncValue.loading();
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(kCustomDownloadPathKey);
    } else {
      await prefs.setString(kCustomDownloadPathKey, path.trim());
    }
    await loadPath();
  }
}

/// Provider for download path
final downloadPathProvider =
    StateNotifierProvider<DownloadPathNotifier, AsyncValue<DownloadPathInfo>>((ref) {
  return DownloadPathNotifier();
});

/// Provider for download quality preference
final downloadQualityProvider =
    StateNotifierProvider<DownloadQualityNotifier, AudioQuality>((ref) {
      return DownloadQualityNotifier();
    });

/// Provider for segmented parallel part count used by downloads.
final downloadParallelPartCountProvider =
    StateNotifierProvider<DownloadParallelPartCountNotifier, int>((ref) {
      return DownloadParallelPartCountNotifier();
    });

/// Provider for minimum file size (MB) before parallel segmented download is used.
final downloadParallelMinSizeMbProvider =
    StateNotifierProvider<DownloadParallelMinSizeMbNotifier, int>((ref) {
      return DownloadParallelMinSizeMbNotifier();
    });

/// Notifier for download quality
class DownloadQualityNotifier extends StateNotifier<AudioQuality> {
  DownloadQualityNotifier() : super(AudioQuality.high) {
    _loadQuality();
  }

  Future<void> _loadQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final qualityIndex = prefs.getInt(kDownloadQualityKey);
    if (qualityIndex != null &&
        qualityIndex >= 0 &&
        qualityIndex < AudioQuality.values.length) {
      state = AudioQuality.values[qualityIndex];
    }
  }

  Future<void> setQuality(AudioQuality quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kDownloadQualityKey, quality.index);
    state = quality;
  }
}

/// Trigger to refresh downloaded tracks (incremented when downloads change)
final downloadedTracksRefreshProvider = StateProvider<int>((ref) => 0);
final downloadedPlaylistsRefreshProvider = StateProvider<int>((ref) => 0);

/// Provider for downloaded tracks from Hive (for display in library/songs tabs)
/// File existence checks run in background isolate to avoid UI jank
final downloadedTracksProvider = FutureProvider<List<Track>>((ref) async {
  // Watch refresh trigger to auto-refresh when downloads change
  ref.watch(downloadedTracksRefreshProvider);

  try {
    final box = HiveService.downloadsBox;

    // Collect download data for isolate processing
    final downloadData = box.values
        .map(
          (e) => _DownloadData(
            trackId: e.trackId,
            title: e.title,
            artist: e.artist,
            album: e.album,
            durationMs: e.durationMs,
            thumbnailUrl: e.thumbnailUrl,
            localPath: e.localPath,
          ),
        )
        .toList();

    // Verify file existence in isolate
    final validPaths = await compute(
      _verifyFilesExistIsolate,
      downloadData.map((d) => d.localPath).toList(),
    );

    final validPathSet = validPaths.toSet();

    // Build track list from valid downloads
    return downloadData
        .where((d) => validPathSet.contains(d.localPath))
        .map(
          (d) => Track(
            id: d.trackId,
            title: d.title,
            artist: d.artist,
            album: d.album,
            duration: Duration(milliseconds: d.durationMs),
            thumbnailUrl: d.thumbnailUrl,
            localFilePath: d.localPath,
          ),
        )
        .toList();
  } catch (e) {
    if (kDebugMode) {
      print('DownloadService: Failed to load downloaded tracks: $e');
    }
    return [];
  }
});

class DownloadedPlaylistSnapshot {
  final String sourcePlaylistId;
  final String title;
  final String? thumbnailUrl;
  final int totalTracks;
  final int downloadedTracks;
  final List<Track> downloadedOrderedTracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DownloadedPlaylistSnapshot({
    required this.sourcePlaylistId,
    required this.title,
    this.thumbnailUrl,
    required this.totalTracks,
    required this.downloadedTracks,
    required this.downloadedOrderedTracks,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Provider for downloaded playlist snapshots with current download completion.
final downloadedPlaylistsProvider =
    FutureProvider<List<DownloadedPlaylistSnapshot>>((ref) async {
      ref.watch(downloadedPlaylistsRefreshProvider);
      ref.watch(downloadedTracksRefreshProvider);

      try {
        final playlists = HiveService.downloadedPlaylistsBox.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final downloadsById = <String, DownloadEntity>{
          for (final e in HiveService.downloadsBox.values) e.trackId: e,
        };

        final snapshots = <DownloadedPlaylistSnapshot>[];
        for (final playlist in playlists) {
          final orderedTracks = <Track>[];
          for (final trackId in playlist.trackIds) {
            final download = downloadsById[trackId];
            if (download == null) continue;
            final localFile = File(download.localPath);
            if (!await localFile.exists()) continue;
            orderedTracks.add(
              Track(
                id: download.trackId,
                title: download.title,
                artist: download.artist,
                album: download.album,
                duration: Duration(milliseconds: download.durationMs),
                thumbnailUrl: download.thumbnailUrl,
                localFilePath: download.localPath,
              ),
            );
          }

          snapshots.add(
            DownloadedPlaylistSnapshot(
              sourcePlaylistId: playlist.sourcePlaylistId,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
              totalTracks: playlist.trackIds.length,
              downloadedTracks: orderedTracks.length,
              downloadedOrderedTracks: orderedTracks,
              createdAt: playlist.createdAt,
              updatedAt: playlist.updatedAt,
            ),
          );
        }
        return snapshots;
      } catch (e) {
        if (kDebugMode) {
          print('DownloadService: Failed to load downloaded playlists: $e');
        }
        return const <DownloadedPlaylistSnapshot>[];
      }
    });

/// Data class for passing download info to isolate
class _DownloadData {
  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? thumbnailUrl;
  final String localPath;

  _DownloadData({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.thumbnailUrl,
    required this.localPath,
  });
}

/// Top-level isolate function to verify file existence
List<String> _verifyFilesExistIsolate(List<String> paths) {
  return paths.where((path) => File(path).existsSync()).toList();
}

/// Download status enum
enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}

class DownloadParallelPartCountNotifier extends StateNotifier<int> {
  DownloadParallelPartCountNotifier()
    : super(kDefaultParallelDownloadPartCount) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getInt(kDownloadParallelPartCountKey) ??
        kDefaultParallelDownloadPartCount;
    state = value.clamp(
      kMinParallelDownloadPartCount,
      kMaxParallelDownloadPartCount,
    );
  }

  Future<void> setPartCount(int value) async {
    final clamped = value.clamp(
      kMinParallelDownloadPartCount,
      kMaxParallelDownloadPartCount,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kDownloadParallelPartCountKey, clamped);
    state = clamped;
  }
}

class DownloadParallelMinSizeMbNotifier extends StateNotifier<int> {
  DownloadParallelMinSizeMbNotifier()
    : super(kDefaultParallelDownloadMinSizeMb) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getInt(kDownloadParallelMinSizeMbKey) ??
        kDefaultParallelDownloadMinSizeMb;
    state = value.clamp(
      kMinParallelDownloadMinSizeMb,
      kMaxParallelDownloadMinSizeMb,
    );
  }

  Future<void> setMinSizeMb(int value) async {
    final clamped = value.clamp(
      kMinParallelDownloadMinSizeMb,
      kMaxParallelDownloadMinSizeMb,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kDownloadParallelMinSizeMbKey, clamped);
    state = clamped;
  }
}

/// Individual download task
class DownloadTask {
  final String trackId;
  final Track track;
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String? error;
  final String? localPath;
  final DateTime startedAt;

  const DownloadTask({
    required this.trackId,
    required this.track,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.localPath,
    required this.startedAt,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? error,
    String? localPath,
  }) => DownloadTask(
    trackId: trackId,
    track: track,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: error ?? this.error,
    localPath: localPath ?? this.localPath,
    startedAt: startedAt,
  );

  String get progressText {
    if (totalBytes == 0) return '0%';
    return '${(progress * 100).toInt()}%';
  }

  String get sizeText {
    if (totalBytes == 0) return '';
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Download manager state
class DownloadManagerState {
  final Map<String, DownloadTask> tasks;
  final List<String> queue; // Track IDs in download queue order
  final bool isDownloading;

  const DownloadManagerState({
    this.tasks = const {},
    this.queue = const [],
    this.isDownloading = false,
  });

  DownloadManagerState copyWith({
    Map<String, DownloadTask>? tasks,
    List<String>? queue,
    bool? isDownloading,
  }) => DownloadManagerState(
    tasks: tasks ?? this.tasks,
    queue: queue ?? this.queue,
    isDownloading: isDownloading ?? this.isDownloading,
  );

  List<DownloadTask> get activeTasks => tasks.values
      .where((t) => t.status == DownloadStatus.downloading)
      .toList();

  List<DownloadTask> get queuedTasks =>
      tasks.values.where((t) => t.status == DownloadStatus.queued).toList();

  List<DownloadTask> get completedTasks =>
      tasks.values.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get failedTasks =>
      tasks.values.where((t) => t.status == DownloadStatus.failed).toList();

  int get totalCompleted => completedTasks.length;

  int get totalStorageBytes =>
      completedTasks.fold(0, (sum, t) => sum + t.totalBytes);

  String get totalStorageText {
    final mb = totalStorageBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Download manager notifier
class DownloadManagerNotifier extends StateNotifier<DownloadManagerState> {
  final YTPlayerUtils _playerUtils;
  final Ref _ref;
  final DownloadNotificationService _notificationService =
      DownloadNotificationService();
  http.Client? _httpClient;
  StreamSubscription? _currentDownload;
  DateTime? _lastNotificationUpdate;
  bool _initialized = false;
  AudioQuality _downloadQuality = AudioQuality.high;
  int _parallelDownloadPartCount = kDefaultParallelDownloadPartCount;
  int _parallelDownloadMinBytes =
      kDefaultParallelDownloadMinSizeMb * 1024 * 1024;
  Timer? _cleanupTimer;
  final Map<String, int> _transientRetryAttempts = <String, int>{};

  DownloadManagerNotifier(this._playerUtils, this._ref)
    : super(const DownloadManagerState()) {
    // Initialize notification service
    _notificationService.initialize();
    // Load persisted downloads
    _loadPersistedDownloads();
    // Load download quality preference
    _loadDownloadQuality();
    // Load parallel download tuning settings.
    _loadParallelDownloadSettings();
    // Start cleanup timer (runs every 30 minutes)
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _cleanupOldCompletedTasks(),
    );
  }

  /// Load download quality from preferences
  Future<void> _loadDownloadQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final qualityIndex = prefs.getInt(kDownloadQualityKey);
    if (qualityIndex != null &&
        qualityIndex >= 0 &&
        qualityIndex < AudioQuality.values.length) {
      _downloadQuality = AudioQuality.values[qualityIndex];
    }
  }

  /// Set download quality (called from provider)
  void setDownloadQuality(AudioQuality quality) {
    _downloadQuality = quality;
  }

  Future<void> _loadParallelDownloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final partCount =
        prefs.getInt(kDownloadParallelPartCountKey) ??
        kDefaultParallelDownloadPartCount;
    final minSizeMb =
        prefs.getInt(kDownloadParallelMinSizeMbKey) ??
        kDefaultParallelDownloadMinSizeMb;
    _parallelDownloadPartCount = partCount.clamp(
      kMinParallelDownloadPartCount,
      kMaxParallelDownloadPartCount,
    );
    final clampedMinSizeMb = minSizeMb.clamp(
      kMinParallelDownloadMinSizeMb,
      kMaxParallelDownloadMinSizeMb,
    );
    _parallelDownloadMinBytes = clampedMinSizeMb * 1024 * 1024;
  }

  void setParallelDownloadPartCount(int value) {
    _parallelDownloadPartCount = value.clamp(
      kMinParallelDownloadPartCount,
      kMaxParallelDownloadPartCount,
    );
  }

  void setParallelDownloadMinSizeMb(int value) {
    final clamped = value.clamp(
      kMinParallelDownloadMinSizeMb,
      kMaxParallelDownloadMinSizeMb,
    );
    _parallelDownloadMinBytes = clamped * 1024 * 1024;
  }

  /// Get downloads directory - uses app-private storage (OuterTune style)
  Future<Directory> getDownloadsDir() async {
    final path = await _getDownloadsDirPath();
    return Directory(path);
  }

  /// Legacy getter for backward compatibility
  Future<Directory> get _downloadsDir => getDownloadsDir();

  /// Load persisted download metadata from Hive
  Future<void> _loadPersistedDownloads() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final downloadsBox = HiveService.downloadsBox;
      final tasks = <String, DownloadTask>{};

      for (final entity in downloadsBox.values) {
        final localPath = entity.localPath;

        // Only restore if file still exists
        if (await File(localPath).exists()) {
          final track = Track(
            id: entity.trackId,
            title: entity.title,
            artist: entity.artist,
            album: entity.album,
            duration: Duration(milliseconds: entity.durationMs),
            thumbnailUrl: entity.thumbnailUrl,
            localFilePath: localPath,
          );

          tasks[entity.trackId] = DownloadTask(
            trackId: entity.trackId,
            track: track,
            status: DownloadStatus.completed,
            progress: 1.0,
            totalBytes: entity.totalBytes,
            downloadedBytes: entity.totalBytes,
            localPath: localPath,
            startedAt: entity.downloadedAt,
          );
        } else {
          // File no longer exists, remove from Hive
          await downloadsBox.delete(entity.trackId);
        }
      }

      if (tasks.isNotEmpty) {
        state = state.copyWith(tasks: tasks);
        if (kDebugMode) {
          print(
            'DownloadService: Loaded ${tasks.length} persisted downloads from Hive',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('DownloadService: Failed to load persisted downloads: $e');
      }
    }
  }

  /// Persist completed download to Hive
  Future<void> _persistDownload(DownloadTask task) async {
    try {
      final entity = DownloadEntity(
        trackId: task.trackId,
        title: task.track.title,
        artist: task.track.artist,
        album: task.track.album,
        durationMs: task.track.duration.inMilliseconds,
        thumbnailUrl: task.track.thumbnailUrl,
        localPath: task.localPath!,
        totalBytes: task.totalBytes,
        downloadedAt: DateTime.now(),
        quality: _downloadQuality.name,
      );

      await HiveService.downloadsBox.put(task.trackId, entity);
      if (kDebugMode) {
        print('DownloadService: Persisted download ${task.trackId} to Hive');
      }
    } catch (e) {
      if (kDebugMode) {
        print('DownloadService: Failed to persist download: $e');
      }
    }
  }

  /// Remove download from Hive
  Future<void> _removeFromHive(String trackId) async {
    try {
      await HiveService.downloadsBox.delete(trackId);
    } catch (e) {
      if (kDebugMode) {
        print('DownloadService: Failed to remove from Hive: $e');
      }
    }
  }

  /// Add track to download queue
  Future<void> addToQueue(Track track) async {
    if (state.tasks.containsKey(track.id)) {
      final existing = state.tasks[track.id]!;
      if (existing.status == DownloadStatus.completed) {
        return; // Already downloaded
      }
      if (existing.status == DownloadStatus.downloading ||
          existing.status == DownloadStatus.queued) {
        return; // Already in progress
      }
    }

    // Duplicate check: check Hive and disk before queueing
    try {
      final hiveEntity = HiveService.downloadsBox.get(track.id);
      if (hiveEntity != null && hiveEntity.localPath.isNotEmpty) {
        final existingFile = File(hiveEntity.localPath);
        if (await existingFile.exists() &&
            await existingFile.length() >= 50 * 1024) {
          if (kDebugMode) {
            print(
              'DownloadService: Track ${track.title} already downloaded at ${existingFile.path}',
            );
          }
          final completedTask = DownloadTask(
            trackId: track.id,
            track: track,
            status: DownloadStatus.completed,
            progress: 1.0,
            localPath: hiveEntity.localPath,
            downloadedBytes: hiveEntity.totalBytes,
            totalBytes: hiveEntity.totalBytes,
            startedAt: hiveEntity.downloadedAt,
          );
          final newTasks = Map<String, DownloadTask>.from(state.tasks);
          newTasks[track.id] = completedTask;
          state = state.copyWith(tasks: newTasks);
          return;
        }
      }
    } catch (_) {}

    final task = DownloadTask(
      trackId: track.id,
      track: track,
      status: DownloadStatus.queued,
      startedAt: DateTime.now(),
    );

    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    newTasks[track.id] = task;

    final newQueue = List<String>.from(state.queue);
    newQueue.add(track.id);

    state = state.copyWith(tasks: newTasks, queue: newQueue);

    // Start download if not already downloading
    _processQueue();
  }

  /// Add multiple tracks to queue
  Future<void> addMultipleToQueue(List<Track> tracks) async {
    for (final track in tracks) {
      await addToQueue(track);
    }
  }

  /// Create/update a downloaded-playlist snapshot and enqueue its tracks.
  Future<void> addPlaylistToQueue({
    required String sourcePlaylistId,
    required String title,
    String? thumbnailUrl,
    required List<Track> tracks,
  }) async {
    if (tracks.isEmpty) return;
    await _upsertDownloadedPlaylistSnapshot(
      sourcePlaylistId: sourcePlaylistId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      tracks: tracks,
    );
    await addMultipleToQueue(tracks);
  }

  Future<void> _upsertDownloadedPlaylistSnapshot({
    required String sourcePlaylistId,
    required String title,
    String? thumbnailUrl,
    required List<Track> tracks,
  }) async {
    final normalizedId = sourcePlaylistId.trim().isEmpty
        ? 'playlist_${title.hashCode}'
        : sourcePlaylistId.trim();

    final trackIds = tracks.map((t) => t.id).toList(growable: false);
    final trackTitles = <String, String>{for (final t in tracks) t.id: t.title};
    final trackArtists = <String, String>{
      for (final t in tracks) t.id: t.artist,
    };

    final box = HiveService.downloadedPlaylistsBox;
    final existing = box.get(normalizedId);
    final now = DateTime.now();
    final entity = DownloadedPlaylistEntity(
      sourcePlaylistId: normalizedId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      trackIds: trackIds,
      trackTitles: trackTitles,
      trackArtists: trackArtists,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await box.put(normalizedId, entity);
    _ref.read(downloadedPlaylistsRefreshProvider.notifier).state++;
  }

  /// Cancel a download
  void cancelDownload(String trackId) {
    if (!state.tasks.containsKey(trackId)) return;
    _transientRetryAttempts.remove(trackId);

    final task = state.tasks[trackId]!;
    if (task.status == DownloadStatus.downloading) {
      _currentDownload?.cancel();
    }

    // Cancel notification
    _notificationService.cancelNotification(trackId);

    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    newTasks[trackId] = task.copyWith(status: DownloadStatus.cancelled);

    final newQueue = List<String>.from(state.queue);
    newQueue.remove(trackId);

    state = state.copyWith(
      tasks: newTasks,
      queue: newQueue,
      isDownloading: false,
    );

    _processQueue();
  }

  /// Remove a completed/failed download
  Future<void> removeDownload(String trackId) async {
    if (!state.tasks.containsKey(trackId)) return;
    _transientRetryAttempts.remove(trackId);

    final task = state.tasks[trackId]!;

    // Delete file if exists
    if (task.localPath != null) {
      try {
        final file = File(task.localPath!);
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {
            print('DownloadService: Deleted file: ${task.localPath}');
          }
        }
        final coverFile = File('${task.localPath!}.cover.jpg');
        if (await coverFile.exists()) {
          await coverFile.delete();
          if (kDebugMode) {
            print('DownloadService: Deleted cover: ${coverFile.path}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error deleting file: $e');
        }
      }
    }

    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    newTasks.remove(trackId);

    final newQueue = List<String>.from(state.queue);
    newQueue.remove(trackId);

    state = state.copyWith(tasks: newTasks, queue: newQueue);

    // Remove from Hive
    await _removeFromHive(trackId);

    // Trigger refresh of downloaded tracks provider
    _ref.read(downloadedTracksRefreshProvider.notifier).state++;
  }

  /// Remove all downloaded tracks
  Future<void> removeAllDownloads() async {
    final trackIds = state.tasks.keys.toList();
    for (final id in trackIds) {
      await removeDownload(id);
    }
  }

  /// Retry a failed download
  void retryDownload(String trackId) {
    if (!state.tasks.containsKey(trackId)) return;

    final task = state.tasks[trackId]!;
    if (task.status != DownloadStatus.failed) return;
    _transientRetryAttempts.remove(trackId);

    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    newTasks[trackId] = task.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      downloadedBytes: 0,
      error: null,
    );

    final newQueue = List<String>.from(state.queue);
    newQueue.add(trackId);

    state = state.copyWith(tasks: newTasks, queue: newQueue);

    _processQueue();
  }

  /// Check if a track is downloaded
  bool isDownloaded(String trackId) {
    final task = state.tasks[trackId];
    return task?.status == DownloadStatus.completed && task?.localPath != null;
  }

  /// Get local path for a downloaded track
  String? getLocalPath(String trackId) {
    final task = state.tasks[trackId];
    if (task?.status == DownloadStatus.completed) {
      return task?.localPath;
    }
    return null;
  }

  /// Process download queue
  void _processQueue() {
    if (state.isDownloading) return;
    if (state.queue.isEmpty) return;

    final nextTrackId = state.queue.first;
    final task = state.tasks[nextTrackId];
    if (task == null) return;

    _downloadTrack(task);
  }

  bool _isTaskCancelled(String trackId) {
    final task = state.tasks[trackId];
    return task?.status == DownloadStatus.cancelled;
  }

  bool _isTransientDownloadError(Object error) {
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is HandshakeException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    const transientHints = <String>[
      'socketexception',
      'timed out',
      'connection reset',
      'connection aborted',
      'network is unreachable',
      'software caused connection abort',
      'failed host lookup',
      'handshake',
      'temporarily unavailable',
      'connection closed before full header was received',
    ];

    for (final hint in transientHints) {
      if (message.contains(hint)) {
        return true;
      }
    }
    return false;
  }

  /// Concurrently fetch lyrics for a track during download
  Future<String?> _fetchLyricsForTrack(Track track) async {
    try {
      // 1. Check Hive cache first
      final cached = HiveService.lyricsBox.get(track.id);
      if (cached != null && !cached.isExpired && cached.hasLyrics) {
        return cached.syncedLyrics ?? cached.plainLyrics;
      }

      // 2. Query lyrics provider with short timeouts so it never blocks downloads
      final info = LyricsSearchInfo(
        videoId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: track.duration.inSeconds,
        localFilePath: track.localFilePath,
      );

      final providers = [
        BetterLyricsProvider(),
        PaxSenixProvider(),
        SimpMusicProvider(),
        LyricsPlusProvider(),
        LRCLibProvider(),
      ];

      LyricResult? bestResult;
      for (final provider in providers) {
        try {
          final res = await provider.search(info).timeout(
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

      if (bestResult != null && bestResult.hasLyrics) {
        if (bestResult.lines != null && bestResult.lines!.isNotEmpty) {
          return bestResult.lines!.toEnhancedLrc();
        }
        return bestResult.lyrics;
      }
    } catch (e) {
      if (kDebugMode) {
        print('DownloadService: Parallel lyrics lookup error: $e');
      }
    }
    return null;
  }

  /// Concurrently fetch cover art image bytes during download
  Future<Uint8List?> _fetchCoverArtBytes(String? thumbnailUrl) async {
    final rawUrl = thumbnailUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;

    final candidates = <String>[
      rawUrl.replaceAll('w120-h120', 'w800-h800'),
      rawUrl.replaceAll('w120-h120', 'w600-h600'),
      rawUrl,
    ];

    for (final url in candidates) {
      try {
        final uri = Uri.tryParse(url);
        if (uri == null) continue;
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        try {
          final req = await client.getUrl(uri);
          final res = await req.close();
          if (res.statusCode == HttpStatus.ok) {
            final builder = BytesBuilder(copy: false);
            await for (final chunk in res) {
              builder.add(chunk);
            }
            final bytes = builder.takeBytes();
            if (bytes.length >= 1024) return bytes;
          }
        } finally {
          client.close(force: true);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<int?> _downloadWithParallelRanges({
    required String trackId,
    required Uri streamUri,
    required File outputFile,
    required int expectedBytes,
    required void Function(int downloadedBytes) onProgress,
  }) async {
    if (_parallelDownloadPartCount < kMinParallelDownloadPartCount) {
      return null;
    }
    if (expectedBytes < _parallelDownloadMinBytes) {
      return null;
    }

    final partCount = min(
      _parallelDownloadPartCount,
      max(2, expectedBytes ~/ (512 * 1024)),
    );

    final parts = <({int start, int end, File file})>[];
    int cursor = 0;
    final basePartSize = expectedBytes ~/ partCount;
    final remainder = expectedBytes % partCount;
    for (int i = 0; i < partCount; i++) {
      final partSize = basePartSize + (i < remainder ? 1 : 0);
      final start = cursor;
      final end = start + partSize - 1;
      cursor = end + 1;
      parts.add((
        start: start,
        end: end,
        file: File('${outputFile.path}.seg$i.part'),
      ));
    }

    if (kDebugMode) {
      print(
        'DownloadService: Trying parallel download for $trackId '
        '($expectedBytes bytes, parts=$partCount)',
      );
    }

    int downloadedBytes = 0;

    Future<void> cleanupParts() async {
      for (final part in parts) {
        if (await part.file.exists()) {
          await part.file.delete();
        }
      }
    }

    try {
      for (final part in parts) {
        if (await part.file.exists()) {
          await part.file.delete();
        }
      }

      Future<void> downloadPart(({int start, int end, File file}) part) async {
        if (_isTaskCancelled(trackId)) {
          throw const _DownloadCancelledException();
        }
        HttpClient? partClient;
        IOSink? partSink;
        try {
          partClient = HttpClient()
            ..connectionTimeout = const Duration(seconds: 20);
          final request = await partClient.getUrl(streamUri);
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=${part.start}-${part.end}',
          );

          final response = await request.close();
          if (response.statusCode != 206) {
            throw HttpException(
              'Range request returned HTTP ${response.statusCode}',
            );
          }

          partSink = part.file.openWrite(mode: FileMode.writeOnly);
          int partBytes = 0;
          await for (final chunk in response) {
            if (_isTaskCancelled(trackId)) {
              throw const _DownloadCancelledException();
            }
            partSink.add(chunk);
            partBytes += chunk.length;
            downloadedBytes += chunk.length;
            onProgress(downloadedBytes);
          }

          await partSink.flush();
          await partSink.close();
          partSink = null;

          final expectedPartBytes = part.end - part.start + 1;
          if (partBytes != expectedPartBytes) {
            throw FormatException(
              'Range part size mismatch ($partBytes vs $expectedPartBytes)',
            );
          }
        } finally {
          if (partSink != null) {
            await partSink.close();
          }
          partClient?.close(force: true);
        }
      }

      await Future.wait(parts.map(downloadPart));

      if (_isTaskCancelled(trackId)) {
        throw const _DownloadCancelledException();
      }

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      final mergeSink = outputFile.openWrite(mode: FileMode.writeOnly);
      try {
        for (final part in parts) {
          await mergeSink.addStream(part.file.openRead());
        }
        await mergeSink.flush();
      } finally {
        await mergeSink.close();
      }

      final mergedBytes = await outputFile.length();
      if (mergedBytes != expectedBytes) {
        throw FormatException(
          'Merged range file size mismatch ($mergedBytes vs $expectedBytes)',
        );
      }

      await cleanupParts();
      return mergedBytes;
    } catch (e) {
      await cleanupParts();
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      if (e is _DownloadCancelledException) {
        rethrow;
      }
      if (kDebugMode) {
        print('DownloadService: Parallel download fallback for $trackId: $e');
      }
      return null;
    }
  }

  /// Download a single track using range-based continuation (OuterTune style)
  /// YouTube serves chunked streams that may not complete in a single GET request
  Future<void> _downloadTrack(DownloadTask task) async {
    state = state.copyWith(isDownloading: true);

    // Update status to downloading
    _updateTask(
      task.trackId,
      task.copyWith(status: DownloadStatus.downloading),
    );

    // Show download started notification
    await _notificationService.showDownloadStarted(
      task.trackId,
      task.track.title,
    );

    try {
      String streamUrl;
      String extension;
      int expectedTotal = 0;

      // Check JioSaavn for 320 kbps stream if enabled and high/max quality
      final prefs = await SharedPreferences.getInstance();
      final jioSaavnEnabled = prefs.getBool(kJioSaavnEnabledKey) ?? true;
      JioSaavnStream? saavnStream;

      if (jioSaavnEnabled &&
          (_downloadQuality == AudioQuality.high ||
              _downloadQuality == AudioQuality.max)) {
        try {
          saavnStream =
              await JioSaavnService.instance.getBestStreamForTrack(task.track);
        } catch (e) {
          if (kDebugMode) {
            print('DownloadService: JioSaavn lookup error: $e');
          }
        }
      }

      if (saavnStream != null && saavnStream.url.isNotEmpty) {
        streamUrl = saavnStream.url;
        extension = saavnStream.format.toLowerCase().contains('mp3')
            ? '.mp3'
            : '.m4a';
        if (kDebugMode) {
          print(
            'DownloadService: Downloading ${task.track.title} via JioSaavn ${saavnStream.kbps ?? 320}kbps ($extension)',
          );
        }
      } else {
        // Fallback to YouTube
        final result = await _playerUtils.playerResponseForDownload(
          task.trackId,
          quality: _downloadQuality,
        );
        if (result.isFailure || result.data == null) {
          throw Exception(result.error ?? 'Failed to get stream URL');
        }

        streamUrl = result.data!.streamUrl;
        final format = result.data!.format;
        expectedTotal = format.contentLength ?? 0;

        // Determine correct file extension based on actual format
        extension = '.opus'; // Default - prefer Opus
        if (format.mimeType.contains('mp4') ||
            format.mimeType.contains('m4a')) {
          extension = '.m4a';
        } else if (format.mimeType.contains('webm') ||
            format.mimeType.contains('opus')) {
          extension = '.opus';
        }

        if (kDebugMode) {
          print('DownloadService: Downloading ${format.mimeType} as $extension');
        }
      }

      // Create file with proper naming: "Artist - Title.ext"
      final dir = await _downloadsDir;
      final sanitizedTitle = _sanitizeFileName(task.track.title);
      final sanitizedArtist = _sanitizeFileName(task.track.artist);
      final fileName = '$sanitizedArtist - $sanitizedTitle$extension';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      // Duplicate prevention
      // Check if file already exists with this name (or any common audio extension)
      final possibleExtensions = [extension, '.m4a', '.mp3', '.opus', '.webm'];
      File? existingFile;
      for (final ext in possibleExtensions) {
        final candidate = File(
          '${dir.path}/$sanitizedArtist - $sanitizedTitle$ext',
        );
        if (await candidate.exists() && await candidate.length() >= 50 * 1024) {
          existingFile = candidate;
          break;
        }
      }

      if (existingFile != null) {
        final existingSize = await existingFile.length();
        if (kDebugMode) {
          print(
            'DownloadService: ${existingFile.path} already exists on disk ($existingSize bytes); adopting it',
          );
        }
        final completedTask = task.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          downloadedBytes: existingSize,
          totalBytes: existingSize,
          localPath: existingFile.path,
        );
        _updateTask(task.trackId, completedTask);
        _transientRetryAttempts.remove(task.trackId);
        await _persistDownload(completedTask);
        _ref.read(downloadedTracksRefreshProvider.notifier).state++;
        await _notificationService.showDownloadCompleted(
          task.trackId,
          task.track.title,
        );
        final newQueue = List<String>.from(state.queue);
        newQueue.remove(task.trackId);
        state = state.copyWith(queue: newQueue, isDownloading: false);
        _processQueue();
        return;
      }

      // Launch parallel lyrics & cover art lookups
      final lyricsFuture = _fetchLyricsForTrack(task.track);
      final coverArtFuture = _fetchCoverArtBytes(task.track.thumbnailUrl);

      // === DOWNLOAD STRATEGY ===
      // 1) Try segmented parallel range download when content length is known.
      // 2) Fallback to the existing robust sequential + range continuation flow.
      int totalDownloaded = 0;
      int retryCount = 0;
      const maxRetries = 5;
      const maxRangeAttempts = 10; // Max range continuation attempts
      bool downloadedWithParallel = false;
      DateTime lastProgressUpdate = DateTime.now();

      void reportProgress({bool force = false}) {
        final now = DateTime.now();
        if (!force &&
            now.difference(lastProgressUpdate).inMilliseconds <= 100) {
          return;
        }
        lastProgressUpdate = now;
        final progress = expectedTotal > 0
            ? (totalDownloaded / expectedTotal).clamp(0.0, 1.0)
            : 0.0;
        _updateTask(
          task.trackId,
          task.copyWith(
            status: DownloadStatus.downloading,
            progress: progress,
            downloadedBytes: totalDownloaded,
            totalBytes: expectedTotal,
          ),
        );
        if (force ||
            _lastNotificationUpdate == null ||
            now.difference(_lastNotificationUpdate!).inMilliseconds > 500) {
          _lastNotificationUpdate = now;
          _notificationService.updateDownloadProgress(
            task.trackId,
            task.track.title,
            progress,
          );
        }
      }

      // Delete any existing partial file before trying either strategy.
      if (await file.exists()) {
        await file.delete();
      }

      if (expectedTotal >= _parallelDownloadMinBytes &&
          _parallelDownloadPartCount >= kMinParallelDownloadPartCount) {
        final parallelBytes = await _downloadWithParallelRanges(
          trackId: task.trackId,
          streamUri: Uri.parse(streamUrl),
          outputFile: file,
          expectedBytes: expectedTotal,
          onProgress: (downloadedBytes) {
            totalDownloaded = downloadedBytes;
            reportProgress();
          },
        );
        if (parallelBytes != null) {
          downloadedWithParallel = true;
          totalDownloaded = parallelBytes;
          reportProgress(force: true);
          if (kDebugMode) {
            print(
              'DownloadService: Parallel download complete for ${task.trackId} ($totalDownloaded bytes)',
            );
          }
        }
      }

      if (!downloadedWithParallel) {
        if (_isTaskCancelled(task.trackId)) {
          throw const _DownloadCancelledException();
        }

        // Existing sequential download + continuation fallback.
        final sink = file.openWrite(mode: FileMode.writeOnly);
        try {
          _httpClient?.close();
          _httpClient = http.Client();
          var request = http.Request('GET', Uri.parse(streamUrl));
          request.headers['Accept-Encoding'] = 'identity';
          request.headers['Connection'] = 'keep-alive';

          var response = await _httpClient!.send(request);

          if (response.statusCode != 200 && response.statusCode != 206) {
            throw Exception('HTTP ${response.statusCode}');
          }

          final responseLength = response.contentLength ?? 0;
          if (responseLength > 0) {
            expectedTotal = responseLength;
          }
          if (kDebugMode) {
            print('DownloadService: Expected total size: $expectedTotal bytes');
          }

          await for (final chunk in response.stream) {
            if (_isTaskCancelled(task.trackId)) {
              throw const _DownloadCancelledException();
            }
            sink.add(chunk);
            totalDownloaded += chunk.length;
            reportProgress();
          }

          if (kDebugMode) {
            print(
              'DownloadService: Initial download got $totalDownloaded bytes',
            );
          }

          int rangeAttempts = 0;
          while (expectedTotal > 0 &&
              totalDownloaded < expectedTotal &&
              rangeAttempts < maxRangeAttempts) {
            if (_isTaskCancelled(task.trackId)) {
              throw const _DownloadCancelledException();
            }
            rangeAttempts++;
            final missing = expectedTotal - totalDownloaded;
            if (kDebugMode) {
              print(
                'DownloadService: Missing $missing bytes, attempting Range request (attempt $rangeAttempts)',
              );
            }

            await Future.delayed(const Duration(milliseconds: 500));
            if (_isTaskCancelled(task.trackId)) {
              throw const _DownloadCancelledException();
            }

            _httpClient?.close();
            _httpClient = http.Client();
            request = http.Request('GET', Uri.parse(streamUrl));
            request.headers['Accept-Encoding'] = 'identity';
            request.headers['Connection'] = 'keep-alive';
            request.headers['Range'] = 'bytes=$totalDownloaded-';

            try {
              response = await _httpClient!.send(request);

              if (response.statusCode != 200 && response.statusCode != 206) {
                if (kDebugMode) {
                  print(
                    'DownloadService: Range request failed with ${response.statusCode}',
                  );
                }
                break;
              }

              int chunkBytes = 0;
              await for (final chunk in response.stream) {
                if (_isTaskCancelled(task.trackId)) {
                  throw const _DownloadCancelledException();
                }
                sink.add(chunk);
                totalDownloaded += chunk.length;
                chunkBytes += chunk.length;
                reportProgress();
              }

              if (kDebugMode) {
                print(
                  'DownloadService: Range request got $chunkBytes more bytes, total: $totalDownloaded',
                );
              }

              if (chunkBytes == 0) {
                if (kDebugMode) {
                  print(
                    'DownloadService: Server returned empty response, assuming EOF',
                  );
                }
                break;
              }
            } catch (e) {
              if (e is _DownloadCancelledException) {
                rethrow;
              }
              if (kDebugMode) {
                print('DownloadService: Range request error: $e');
              }
              retryCount++;
              if (retryCount >= maxRetries) {
                break;
              }
            }
          }

          await sink.flush();
        } finally {
          await sink.close();
        }
      }

      // === RELAXED VALIDATION (OuterTune style) ===
      // Don't fail on small size mismatches - YouTube is unreliable
      // Trust the file header and minimum size instead

      final downloadedFile = File(filePath);
      if (!await downloadedFile.exists()) {
        throw Exception('Download failed: File was not created');
      }

      final actualFileSize = await downloadedFile.length();
      if (kDebugMode) {
        print(
          'DownloadService: Final file size: $actualFileSize bytes (expected: $expectedTotal)',
        );
      }

      // Check minimum file size (audio files should be at least 50KB)
      const minFileSize = 50 * 1024; // 50KB
      if (actualFileSize < minFileSize) {
        if (kDebugMode) {
          print(
            'DownloadService: File too small ($actualFileSize bytes), likely corrupted',
          );
        }
        await downloadedFile.delete();
        throw Exception(
          'Download corrupted: File too small (${(actualFileSize / 1024).toStringAsFixed(1)} KB)',
        );
      }

      // Check size difference - only fail if more than 5% missing
      if (expectedTotal > 0) {
        final missingBytes = expectedTotal - actualFileSize;
        final percentMissing = (missingBytes / expectedTotal) * 100;

        if (missingBytes > 0) {
          if (kDebugMode) {
            print(
              'DownloadService: Missing $missingBytes bytes (${percentMissing.toStringAsFixed(1)}%)',
            );
          }
        }

        // Accept up to 5% missing (OuterTune tolerates this)
        if (percentMissing > 5.0) {
          await downloadedFile.delete();
          throw Exception(
            'Download too incomplete: Missing ${percentMissing.toStringAsFixed(1)}% of file',
          );
        }
      }

      // Verify file header - this is the most reliable check
      final isValidAudio = await _verifyAudioFileHeader(
        downloadedFile,
        extension,
      );
      if (!isValidAudio) {
        if (kDebugMode) {
          print('DownloadService: File header verification failed');
        }
        await downloadedFile.delete();
        throw Exception('Download corrupted: Invalid audio file format');
      }

      if (kDebugMode) {
        print(
          'DownloadService: Download verified successfully - ${(actualFileSize / 1024 / 1024).toStringAsFixed(2)} MB',
        );
      }
      // === END VALIDATION ===

      // Await parallel lyrics and cover art (already fetched while streaming)
      final lyricsLrc = await lyricsFuture;
      final coverBytes = await coverArtFuture;

      // In-file metadata tagging
      // Embeds Title, Artist, Album, Synced Lyrics, and Artwork directly into the audio container
      await MediaTagger.tagFile(
        audioFile: downloadedFile,
        track: task.track,
        lyrics: lyricsLrc,
        coverArtBytes: coverBytes,
      );

      final finalFileSize = await downloadedFile.length();

      // Mark as completed
      final completedTask = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        downloadedBytes: finalFileSize,
        totalBytes: finalFileSize,
        localPath: filePath,
      );
      _updateTask(task.trackId, completedTask);
      _transientRetryAttempts.remove(task.trackId);

      // Persist to Hive for next app restart
      await _persistDownload(completedTask);

      // Trigger refresh of downloaded tracks provider
      _ref.read(downloadedTracksRefreshProvider.notifier).state++;

      // Show completion notification
      await _notificationService.showDownloadCompleted(
        task.trackId,
        task.track.title,
      );

      // Remove from queue
      final newQueue = List<String>.from(state.queue);
      newQueue.remove(task.trackId);
      state = state.copyWith(queue: newQueue, isDownloading: false);

      // Process next
      _processQueue();
    } on _DownloadCancelledException {
      if (kDebugMode) {
        print('DownloadService: Download cancelled: ${task.trackId}');
      }

      // Best-effort cleanup of partial output file.
      try {
        final dir = await _downloadsDir;
        final sanitizedTitle = _sanitizeFileName(task.track.title);
        final sanitizedArtist = _sanitizeFileName(task.track.artist);
        final possibleExtensions = const <String>['.opus', '.m4a', '.webm'];
        for (final ext in possibleExtensions) {
          final candidate = File(
            '${dir.path}/$sanitizedArtist - $sanitizedTitle$ext',
          );
          if (await candidate.exists()) {
            await candidate.delete();
          }
          final coverCandidate = File(
            '${dir.path}/$sanitizedArtist - $sanitizedTitle$ext.cover.jpg',
          );
          if (await coverCandidate.exists()) {
            await coverCandidate.delete();
          }
        }
      } catch (_) {}

      await _notificationService.cancelNotification(task.trackId);
      _transientRetryAttempts.remove(task.trackId);

      final currentTask = state.tasks[task.trackId];
      if (currentTask != null &&
          currentTask.status != DownloadStatus.cancelled) {
        _updateTask(
          task.trackId,
          task.copyWith(status: DownloadStatus.cancelled, error: null),
        );
      }

      final newQueue = List<String>.from(state.queue);
      newQueue.remove(task.trackId);
      state = state.copyWith(queue: newQueue, isDownloading: false);
      _processQueue();
    } catch (e) {
      if (kDebugMode) {
        print('Download error: $e');
      }

      final isTransient = _isTransientDownloadError(e);
      if (isTransient) {
        final attempt = (_transientRetryAttempts[task.trackId] ?? 0) + 1;
        _transientRetryAttempts[task.trackId] = attempt;

        if (attempt <= kMaxTransientDownloadRetries) {
          final retryDelaySeconds = min(30, 2 + (attempt * 3));
          if (kDebugMode) {
            print(
              'DownloadService: Transient error for $task.trackId, retry $attempt/$kMaxTransientDownloadRetries in $retryDelaySeconds s',
            );
          }

          _updateTask(
            task.trackId,
            task.copyWith(
              status: DownloadStatus.queued,
              error: 'Retrying ($attempt/$kMaxTransientDownloadRetries)...',
            ),
          );

          state = state.copyWith(isDownloading: false);
          Future<void>.delayed(Duration(seconds: retryDelaySeconds), () {
            final current = state.tasks[task.trackId];
            if (current == null || current.status == DownloadStatus.cancelled) {
              return;
            }
            _processQueue();
          });
          return;
        }
      }

      _transientRetryAttempts.remove(task.trackId);

      _updateTask(
        task.trackId,
        task.copyWith(status: DownloadStatus.failed, error: e.toString()),
      );

      // Show failure notification
      await _notificationService.showDownloadFailed(
        task.trackId,
        task.track.title,
        e.toString(),
      );

      // Remove from queue
      final newQueue = List<String>.from(state.queue);
      newQueue.remove(task.trackId);
      state = state.copyWith(queue: newQueue, isDownloading: false);

      // Process next
      _processQueue();
    }
  }

  void _updateTask(String trackId, DownloadTask task) {
    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    newTasks[trackId] = task;
    state = state.copyWith(tasks: newTasks);
  }

  /// Verify audio file header matches expected format
  /// Returns true if the file appears to be a valid audio file
  Future<bool> _verifyAudioFileHeader(File file, String extension) async {
    try {
      final bytes = await file.openRead(0, 12).first;
      if (bytes.length < 4) return false;

      // Check for M4A/MP4 format (ftyp header)
      // M4A files start with: [size bytes] 'ftyp' [brand]
      if (extension == '.m4a') {
        // Look for 'ftyp' at byte 4 (after size field)
        if (bytes.length >= 8) {
          final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
          if (ftyp == 'ftyp') {
            if (kDebugMode) {
              print('DownloadService: Valid M4A/MP4 header detected');
            }
            return true;
          }
        }
        // Also check if it starts with 'ftyp' directly (some files)
        final start = String.fromCharCodes(bytes.sublist(0, 4));
        if (start == 'ftyp') {
          if (kDebugMode) {
            print('DownloadService: Valid M4A/MP4 header detected (variant)');
          }
          return true;
        }
        if (kDebugMode) {
          print(
            'DownloadService: Invalid M4A header - got: ${bytes.sublist(0, 8)}',
          );
        }
        return false;
      }

      // Check for Opus/WebM format (EBML/WebM header)
      if (extension == '.opus' || extension == '.webm') {
        // WebM files start with EBML header: 0x1A 0x45 0xDF 0xA3
        if (bytes[0] == 0x1A &&
            bytes[1] == 0x45 &&
            bytes[2] == 0xDF &&
            bytes[3] == 0xA3) {
          if (kDebugMode) {
            print('DownloadService: Valid WebM/Opus header detected');
          }
          return true;
        }
        // Also check for OggS header (some Opus files)
        final start = String.fromCharCodes(bytes.sublist(0, 4));
        if (start == 'OggS') {
          if (kDebugMode) {
            print('DownloadService: Valid Ogg/Opus header detected');
          }
          return true;
        }
        if (kDebugMode) {
          print(
            'DownloadService: Invalid Opus/WebM header - got: ${bytes.sublist(0, 8)}',
          );
        }
        return false;
      }

      // Check for MP3 format (ID3 or sync bytes)
      if (extension == '.mp3') {
        // ID3 tag: starts with 'ID3'
        final id3 = String.fromCharCodes(bytes.sublist(0, 3));
        if (id3 == 'ID3') {
          if (kDebugMode) {
            print('DownloadService: Valid MP3 (ID3) header detected');
          }
          return true;
        }
        // MP3 sync: 0xFF 0xFB, 0xFF 0xFA, 0xFF 0xF3, 0xFF 0xF2
        if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
          if (kDebugMode) {
            print('DownloadService: Valid MP3 sync header detected');
          }
          return true;
        }
        return false;
      }

      // Unknown format - allow it (might be valid)
      if (kDebugMode) {
        print('DownloadService: Unknown format $extension, allowing');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('DownloadService: Header verification error: $e');
      }
      return false;
    }
  }

  /// Clear all completed downloads
  Future<void> clearCompleted() async {
    for (final task in state.completedTasks) {
      await removeDownload(task.trackId);
    }
  }

  /// Clear all failed downloads
  void clearFailed() {
    final failedIds = state.failedTasks.map((t) => t.trackId).toList();
    final newTasks = Map<String, DownloadTask>.from(state.tasks);
    for (final id in failedIds) {
      newTasks.remove(id);
    }
    state = state.copyWith(tasks: newTasks);
  }

  /// Remove old completed tasks from memory to prevent memory leaks
  /// Keeps the last hour of completed downloads in memory, older ones are only in Hive
  void _cleanupOldCompletedTasks() {
    final cutoffTime = DateTime.now().subtract(const Duration(hours: 1));
    final newTasks = Map<String, DownloadTask>.from(state.tasks);

    final toRemove = <String>[];
    for (final entry in newTasks.entries) {
      final task = entry.value;
      // Only remove completed tasks older than 1 hour
      if (task.status == DownloadStatus.completed &&
          task.startedAt.isBefore(cutoffTime)) {
        toRemove.add(entry.key);
      }
    }

    if (toRemove.isNotEmpty) {
      for (final id in toRemove) {
        newTasks.remove(id);
      }
      state = state.copyWith(tasks: newTasks);
      if (kDebugMode) {
        print(
          'DownloadService: Cleaned up ${toRemove.length} old completed tasks from memory',
        );
      }
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _currentDownload?.cancel();
    _httpClient?.close();
    super.dispose();
  }
}

/// Provider for YTPlayerUtils
final ytPlayerUtilsProvider = Provider<YTPlayerUtils>((ref) {
  return YTPlayerUtils.instance;
});

/// Provider for download manager
final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, DownloadManagerState>((ref) {
      final playerUtils = ref.watch(ytPlayerUtilsProvider);
      return DownloadManagerNotifier(playerUtils, ref);
    });

/// Provider to check if a specific track is downloaded
final isTrackDownloadedProvider = Provider.family<bool, String>((ref, trackId) {
  final downloadState = ref.watch(downloadManagerProvider);
  return downloadState.tasks[trackId]?.status == DownloadStatus.completed;
});

/// Sanitize a string for use as a filename
String _sanitizeFileName(String name) {
  // Remove or replace invalid filename characters
  return name
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Provider for download progress of a specific track
final trackDownloadProgressProvider = Provider.family<double?, String>((
  ref,
  trackId,
) {
  final downloadState = ref.watch(downloadManagerProvider);
  final task = downloadState.tasks[trackId];
  if (task == null) return null;
  if (task.status == DownloadStatus.completed) return 1.0;
  if (task.status == DownloadStatus.downloading) return task.progress;
  return null;
});
