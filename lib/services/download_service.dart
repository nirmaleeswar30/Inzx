import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../core/services/cache/hive_service.dart';
import '../data/entities/download_entity.dart';
import 'playback/yt_player_utils.dart';
import 'playback/playback_data.dart';
import 'notification_service.dart';

const String kDownloadQualityKey = 'download_quality';

/// Get downloads directory path - uses app-private storage (OuterTune style)
/// This avoids permission issues and keeps files app-contained
Future<String> _getDownloadsDirPath() async {
  // Use app-private external storage (OuterTune style)
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
    if (kDebugMode) {print('DownloadService: Cannot use external storage: $e');}
  }

  // Ultimate fallback: app documents directory
  final appDir = await getApplicationDocumentsDirectory();
  final downloadsDir = Directory('${appDir.path}/audio');
  if (!await downloadsDir.exists()) {
    await downloadsDir.create(recursive: true);
  }
  return downloadsDir.path;
}

/// Provider for download path - uses app-private storage
/// Returns the current download directory path
final downloadPathProvider = FutureProvider<String>((ref) async {
  return await _getDownloadsDirPath();
});

/// Provider for download quality preference
final downloadQualityProvider =
    StateNotifierProvider<DownloadQualityNotifier, AudioQuality>((ref) {
      return DownloadQualityNotifier();
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
    if (kDebugMode) {print('DownloadService: Failed to load downloaded tracks: $e');}
    return [];
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

  DownloadManagerNotifier(this._playerUtils, this._ref)
    : super(const DownloadManagerState()) {
    // Initialize notification service
    _notificationService.initialize();
    // Load persisted downloads
    _loadPersistedDownloads();
    // Load download quality preference
    _loadDownloadQuality();
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
        if (kDebugMode) {print(
          'DownloadService: Loaded ${tasks.length} persisted downloads from Hive',
        );}
      }
    } catch (e) {
      if (kDebugMode) {print('DownloadService: Failed to load persisted downloads: $e');}
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
      if (kDebugMode) {print('DownloadService: Persisted download ${task.trackId} to Hive');}
    } catch (e) {
      if (kDebugMode) {print('DownloadService: Failed to persist download: $e');}
    }
  }

  /// Remove download from Hive
  Future<void> _removeFromHive(String trackId) async {
    try {
      await HiveService.downloadsBox.delete(trackId);
    } catch (e) {
      if (kDebugMode) {print('DownloadService: Failed to remove from Hive: $e');}
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

  /// Cancel a download
  void cancelDownload(String trackId) {
    if (!state.tasks.containsKey(trackId)) return;

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

    final task = state.tasks[trackId]!;

    // Delete file if exists
    if (task.localPath != null) {
      try {
        final file = File(task.localPath!);
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {print('DownloadService: Deleted file: ${task.localPath}');}
        }
      } catch (e) {
        if (kDebugMode) {print('Error deleting file: $e');}
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

  /// Retry a failed download
  void retryDownload(String trackId) {
    if (!state.tasks.containsKey(trackId)) return;

    final task = state.tasks[trackId]!;
    if (task.status != DownloadStatus.failed) return;

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
      // Get stream format - prefer Opus/WebM (more reliable for YouTube downloads)
      final result = await _playerUtils.playerResponseForDownload(
        task.trackId,
        quality: _downloadQuality,
      );
      if (result.isFailure || result.data == null) {
        throw Exception(result.error ?? 'Failed to get stream URL');
      }

      final streamUrl = result.data!.streamUrl;
      final format = result.data!.format;

      // Determine correct file extension based on actual format
      String extension = '.opus'; // Default - prefer Opus
      if (format.mimeType.contains('mp4') || format.mimeType.contains('m4a')) {
        extension = '.m4a';
      } else if (format.mimeType.contains('webm') ||
          format.mimeType.contains('opus')) {
        extension = '.opus';
      }

      if (kDebugMode) {print('DownloadService: Downloading ${format.mimeType} as $extension');}

      // Create file with proper naming: "Artist - Title.ext"
      final dir = await _downloadsDir;
      final sanitizedTitle = _sanitizeFileName(task.track.title);
      final sanitizedArtist = _sanitizeFileName(task.track.artist);
      final fileName = '$sanitizedArtist - $sanitizedTitle$extension';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      // === RANGE-BASED DOWNLOAD (OuterTune style) ===
      // YouTube streams are chunked - we need to handle partial responses
      // and continue with Range requests until we get the complete file

      int totalDownloaded = 0;
      int expectedTotal = 0;
      int retryCount = 0;
      const maxRetries = 5;
      const maxRangeAttempts = 10; // Max range continuation attempts

      // Delete any existing partial file
      if (await file.exists()) {
        await file.delete();
      }

      // Open file for writing
      final sink = file.openWrite(mode: FileMode.writeOnly);
      DateTime lastProgressUpdate = DateTime.now();

      try {
        // Initial request (no range header)
        _httpClient = http.Client();
        var request = http.Request('GET', Uri.parse(streamUrl));
        request.headers['Accept-Encoding'] = 'identity';
        request.headers['Connection'] = 'keep-alive';

        var response = await _httpClient!.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('HTTP ${response.statusCode}');
        }

        expectedTotal = response.contentLength ?? 0;
        if (kDebugMode) {print('DownloadService: Expected total size: $expectedTotal bytes');}

        // Download initial response
        await for (final chunk in response.stream) {
          sink.add(chunk);
          totalDownloaded += chunk.length;

          // Throttled progress updates
          final now = DateTime.now();
          if (now.difference(lastProgressUpdate).inMilliseconds > 100) {
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

            // Notification update (throttled)
            if (_lastNotificationUpdate == null ||
                now.difference(_lastNotificationUpdate!).inMilliseconds > 500) {
              _lastNotificationUpdate = now;
              _notificationService.updateDownloadProgress(
                task.trackId,
                task.track.title,
                progress,
              );
            }
          }
        }

        if (kDebugMode) {print('DownloadService: Initial download got $totalDownloaded bytes');}

        // === RANGE CONTINUATION ===
        // If we didn't get the full file, continue with Range requests
        int rangeAttempts = 0;
        while (expectedTotal > 0 &&
            totalDownloaded < expectedTotal &&
            rangeAttempts < maxRangeAttempts) {
          rangeAttempts++;
          final missing = expectedTotal - totalDownloaded;
          if (kDebugMode) {print(
            'DownloadService: Missing $missing bytes, attempting Range request (attempt $rangeAttempts)',
          );}

          // Small delay before retry
          await Future.delayed(const Duration(milliseconds: 500));

          // Create new request with Range header
          _httpClient?.close();
          _httpClient = http.Client();
          request = http.Request('GET', Uri.parse(streamUrl));
          request.headers['Accept-Encoding'] = 'identity';
          request.headers['Connection'] = 'keep-alive';
          request.headers['Range'] = 'bytes=$totalDownloaded-';

          try {
            response = await _httpClient!.send(request);

            // 206 Partial Content is expected for range requests
            // 200 OK with full content is also acceptable (server ignores range)
            if (response.statusCode != 200 && response.statusCode != 206) {
              if (kDebugMode) {print(
                'DownloadService: Range request failed with ${response.statusCode}',
              );}
              break;
            }

            int chunkBytes = 0;
            await for (final chunk in response.stream) {
              sink.add(chunk);
              totalDownloaded += chunk.length;
              chunkBytes += chunk.length;

              // Progress update
              final now = DateTime.now();
              if (now.difference(lastProgressUpdate).inMilliseconds > 100) {
                lastProgressUpdate = now;
                final progress = (totalDownloaded / expectedTotal).clamp(
                  0.0,
                  1.0,
                );

                _updateTask(
                  task.trackId,
                  task.copyWith(
                    status: DownloadStatus.downloading,
                    progress: progress,
                    downloadedBytes: totalDownloaded,
                    totalBytes: expectedTotal,
                  ),
                );
              }
            }

            if (kDebugMode) {print(
              'DownloadService: Range request got $chunkBytes more bytes, total: $totalDownloaded',
            );}

            // If we got 0 bytes, server has nothing more
            if (chunkBytes == 0) {
              if (kDebugMode) {print(
                'DownloadService: Server returned empty response, assuming EOF',
              );}
              break;
            }
          } catch (e) {
            if (kDebugMode) {print('DownloadService: Range request error: $e');}
            retryCount++;
            if (retryCount >= maxRetries) {
              break;
            }
          }
        }

        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      }

      // === RELAXED VALIDATION (OuterTune style) ===
      // Don't fail on small size mismatches - YouTube is unreliable
      // Trust the file header and minimum size instead

      final downloadedFile = File(filePath);
      if (!await downloadedFile.exists()) {
        throw Exception('Download failed: File was not created');
      }

      final actualFileSize = await downloadedFile.length();
      if (kDebugMode) {print(
        'DownloadService: Final file size: $actualFileSize bytes (expected: $expectedTotal)',
      );}

      // Check minimum file size (audio files should be at least 50KB)
      const minFileSize = 50 * 1024; // 50KB
      if (actualFileSize < minFileSize) {
        if (kDebugMode) {print(
          'DownloadService: File too small ($actualFileSize bytes), likely corrupted',
        );}
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
          if (kDebugMode) {print(
            'DownloadService: Missing $missingBytes bytes (${percentMissing.toStringAsFixed(1)}%)',
          );}
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
        if (kDebugMode) {print('DownloadService: File header verification failed');}
        await downloadedFile.delete();
        throw Exception('Download corrupted: Invalid audio file format');
      }

      if (kDebugMode) {print(
        'DownloadService: Download verified successfully - ${(actualFileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );}
      // === END VALIDATION ===

      // Mark as completed
      final completedTask = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        downloadedBytes: actualFileSize,
        totalBytes: actualFileSize,
        localPath: filePath,
      );
      _updateTask(task.trackId, completedTask);

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
    } catch (e) {
      if (kDebugMode) {print('Download error: $e');}

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
            if (kDebugMode) {print('DownloadService: Valid M4A/MP4 header detected');}
            return true;
          }
        }
        // Also check if it starts with 'ftyp' directly (some files)
        final start = String.fromCharCodes(bytes.sublist(0, 4));
        if (start == 'ftyp') {
          if (kDebugMode) {print('DownloadService: Valid M4A/MP4 header detected (variant)');}
          return true;
        }
        if (kDebugMode) {print(
          'DownloadService: Invalid M4A header - got: ${bytes.sublist(0, 8)}',
        );}
        return false;
      }

      // Check for Opus/WebM format (EBML/WebM header)
      if (extension == '.opus' || extension == '.webm') {
        // WebM files start with EBML header: 0x1A 0x45 0xDF 0xA3
        if (bytes[0] == 0x1A &&
            bytes[1] == 0x45 &&
            bytes[2] == 0xDF &&
            bytes[3] == 0xA3) {
          if (kDebugMode) {print('DownloadService: Valid WebM/Opus header detected');}
          return true;
        }
        // Also check for OggS header (some Opus files)
        final start = String.fromCharCodes(bytes.sublist(0, 4));
        if (start == 'OggS') {
          if (kDebugMode) {print('DownloadService: Valid Ogg/Opus header detected');}
          return true;
        }
        if (kDebugMode) {print(
          'DownloadService: Invalid Opus/WebM header - got: ${bytes.sublist(0, 8)}',
        );}
        return false;
      }

      // Check for MP3 format (ID3 or sync bytes)
      if (extension == '.mp3') {
        // ID3 tag: starts with 'ID3'
        final id3 = String.fromCharCodes(bytes.sublist(0, 3));
        if (id3 == 'ID3') {
          if (kDebugMode) {print('DownloadService: Valid MP3 (ID3) header detected');}
          return true;
        }
        // MP3 sync: 0xFF 0xFB, 0xFF 0xFA, 0xFF 0xF3, 0xFF 0xF2
        if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
          if (kDebugMode) {print('DownloadService: Valid MP3 sync header detected');}
          return true;
        }
        return false;
      }

      // Unknown format - allow it (might be valid)
      if (kDebugMode) {print('DownloadService: Unknown format $extension, allowing');}
      return true;
    } catch (e) {
      if (kDebugMode) {print('DownloadService: Header verification error: $e');}
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

  @override
  void dispose() {
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
