import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import '../models/models.dart';
import '../core/services/cache/hive_service.dart';
import '../data/entities/track_entity.dart';
import '../data/entities/download_entity.dart';
import 'safe_audio_metadata_reader.dart';
import 'local_artwork_service.dart';

/// Provider for scanned local music folders
final localMusicFoldersProvider =
    StateNotifierProvider<LocalMusicFoldersNotifier, List<String>>((ref) {
      return LocalMusicFoldersNotifier();
    });

/// Provider for scanned local tracks
final localTracksProvider =
    StateNotifierProvider<LocalTracksNotifier, List<Track>>((ref) {
      return LocalTracksNotifier();
    });

/// Provider for scan progress
final scanProgressProvider = StateProvider<ScanProgress?>((ref) => null);

/// Scan progress state
class ScanProgress {
  final int scannedFiles;
  final int totalFiles;
  final String currentFile;
  final bool isComplete;

  ScanProgress({
    this.scannedFiles = 0,
    this.totalFiles = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => totalFiles > 0 ? scannedFiles / totalFiles : 0;
}

/// Local music folders notifier
class LocalMusicFoldersNotifier extends StateNotifier<List<String>> {
  LocalMusicFoldersNotifier() : super([]) {
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    try {
      final box = HiveService.localMusicFoldersBox;
      final rawFolders = box.values.toList();
      final validFolders =
          rawFolders.where((p) => Directory(p).existsSync()).toList();
      state = validFolders;
      if (validFolders.length != rawFolders.length) {
        await _persist();
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalMusicFoldersNotifier: Load error: $e');
      }
    }
  }

  Future<void> _persist() async {
    try {
      final box = HiveService.localMusicFoldersBox;
      await box.clear();
      if (state.isNotEmpty) {
        final entries = {for (final p in state) p: p};
        await box.putAll(entries);
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalMusicFoldersNotifier: Persist error: $e');
      }
    }
  }

  void addFolder(String path) {
    if (!state.contains(path)) {
      state = [...state, path];
      _persist();
    }
  }

  void removeFolder(String path) {
    state = state.where((p) => p != path).toList();
    _persist();
  }

  void clear() {
    state = [];
    _persist();
  }
}

/// Local tracks notifier
class LocalTracksNotifier extends StateNotifier<List<Track>> {
  StreamSubscription<Track>? _enrichSubscription;

  LocalTracksNotifier() : super([]) {
    _loadPersisted();
    _enrichSubscription = LocalArtworkService.onTrackEnriched.listen((updatedTrack) {
      final index = state.indexWhere((t) => t.id == updatedTrack.id);
      if (index != -1) {
        final updatedList = List<Track>.from(state);
        updatedList[index] = updatedTrack;
        state = updatedList;
      }
    });
  }

  @override
  void dispose() {
    _enrichSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPersisted() async {
    try {
      final box = HiveService.localMusicTracksBox;
      final allTracks = box.values.map(_trackFromEntity).toList();
      final validTracks = <Track>[];
      final missingIds = <String>[];

      for (final track in allTracks) {
        final filePath = track.localFilePath;
        if (filePath != null &&
            filePath.isNotEmpty &&
            File(filePath).existsSync()) {
          validTracks.add(track);
        } else {
          missingIds.add(track.id);
        }
      }

      state = validTracks;
      if (missingIds.isNotEmpty) {
        await box.deleteAll(missingIds);
        if (kDebugMode) {
          print(
            'LocalTracksNotifier: Pruned ${missingIds.length} missing tracks from Hive',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalTracksNotifier: Load error: $e');
      }
    }
  }

  /// Prune tracks whose files no longer exist on disk
  Future<void> pruneMissingFiles() async {
    final validTracks = <Track>[];
    final missingIds = <String>[];

    for (final track in state) {
      final filePath = track.localFilePath;
      if (filePath != null &&
          filePath.isNotEmpty &&
          File(filePath).existsSync()) {
        validTracks.add(track);
      } else {
        missingIds.add(track.id);
      }
    }

    if (missingIds.isNotEmpty) {
      state = validTracks;
      try {
        await HiveService.localMusicTracksBox.deleteAll(missingIds);
        if (kDebugMode) {
          print(
            'LocalTracksNotifier: pruneMissingFiles pruned ${missingIds.length} tracks',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('LocalTracksNotifier: pruneMissingFiles error: $e');
        }
      }
    }
  }

  void addTracks(List<Track> tracks) {
    final existingIds = state.map((t) => t.id).toSet();
    final newTracks = tracks.where((t) => !existingIds.contains(t.id)).toList();
    state = [...state, ...newTracks];
    if (newTracks.isNotEmpty) {
      _persistNewTracks(newTracks);
    }
  }

  /// Syncs a specific folder with fresh scanned tracks, removing deleted/moved files
  Future<void> syncFolderTracks(
    String folderPath,
    List<Track> freshTracks,
  ) async {
    final normalizedFolder = _normalizePath(folderPath);
    final folderWithSep = '$normalizedFolder/';

    final removedIds = <String>[];
    final otherTracks = <Track>[];

    for (final track in state) {
      final filePath = track.localFilePath;
      if (filePath == null || filePath.isEmpty) {
        otherTracks.add(track);
        continue;
      }
      final normalizedFile = _normalizePath(filePath);
      final isInFolder =
          normalizedFile == normalizedFolder ||
          normalizedFile.startsWith(folderWithSep);

      if (isInFolder) {
        removedIds.add(track.id);
      } else {
        otherTracks.add(track);
      }
    }

    state = [...otherTracks, ...freshTracks];

    try {
      final box = HiveService.localMusicTracksBox;
      if (removedIds.isNotEmpty) {
        await box.deleteAll(removedIds);
      }
      if (freshTracks.isNotEmpty) {
        final entities = {for (final t in freshTracks) t.id: _trackToEntity(t)};
        await _batchPutHiveEntities(box, entities);
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalTracksNotifier: syncFolderTracks error: $e');
      }
    }
  }

  /// Replaces tracks for all given folders with fresh tracks, removing deleted/moved files
  Future<void> syncAllFolders(
    List<String> folders,
    List<Track> allScannedTracks,
  ) async {
    final normalizedFolders = folders.map(_normalizePath).toList();

    final remaining = <Track>[];
    final removedIds = <String>[];

    for (final track in state) {
      final filePath = track.localFilePath;
      if (filePath == null || filePath.isEmpty) {
        remaining.add(track);
        continue;
      }
      final normalizedFile = _normalizePath(filePath);
      final isInTrackedFolder = normalizedFolders.any((f) {
        final fWithSep = '$f/';
        return normalizedFile == f || normalizedFile.startsWith(fWithSep);
      });

      if (isInTrackedFolder) {
        removedIds.add(track.id);
      } else {
        remaining.add(track);
      }
    }

    state = [...remaining, ...allScannedTracks];

    try {
      final box = HiveService.localMusicTracksBox;
      if (removedIds.isNotEmpty) {
        await box.deleteAll(removedIds);
      }
      if (allScannedTracks.isNotEmpty) {
        final entities = {
          for (final t in allScannedTracks) t.id: _trackToEntity(t),
        };
        await _batchPutHiveEntities(box, entities);
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalTracksNotifier: syncAllFolders error: $e');
      }
    }
  }

  /// Write entities to Hive in small batches yielding to the event loop to prevent UI hangs and GC memory spikes
  static Future<void> _batchPutHiveEntities(
    Box<TrackEntity> box,
    Map<String, TrackEntity> entities,
  ) async {
    const batchSize = 100;
    final entries = entities.entries.toList();
    for (int i = 0; i < entries.length; i += batchSize) {
      final chunk = Map.fromEntries(
        entries.sublist(i, min(i + batchSize, entries.length)),
      );
      await box.putAll(chunk);
      if (i + batchSize < entries.length) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  void clear() {
    state = [];
    HiveService.localMusicTracksBox.clear();
  }

  /// Delete a single track: deletes the physical file from disk (if requested),
  /// and only upon successful disk deletion removes from state and Hive.
  Future<bool> deleteTrack(Track track, {bool deleteFileFromDisk = true}) async {
    // 1. Delete file from disk if requested
    if (deleteFileFromDisk &&
        track.localFilePath != null &&
        track.localFilePath!.isNotEmpty) {
      final file = File(track.localFilePath!);
      bool fileDeleted = false;

      try {
        if (await file.exists()) {
          await file.delete();
          fileDeleted = true;
        } else {
          // File does not exist on disk, consider it deleted
          fileDeleted = true;
        }
      } catch (e) {
        if (kDebugMode) {
          print('LocalTracksNotifier: Initial file delete error: $e');
        }

        // On Android, scoped storage may block direct POSIX deletion with PathNotFoundException
        // (errno = 2) if MANAGE_EXTERNAL_STORAGE is not granted.
        // Attempt to request storage deletion permission and retry.
        if (Platform.isAndroid) {
          try {
            final granted = await LocalMusicScanner.requestDeleteStoragePermission();
            if (granted && await file.exists()) {
              await file.delete();
              fileDeleted = true;
            }
          } catch (retryError) {
            if (kDebugMode) {
              print('LocalTracksNotifier: Retry file delete error: $retryError');
            }
          }
        }
      }

      // If physical deletion failed and the file still exists, abort to prevent
      // desynchronization between disk and library state.
      if (!fileDeleted && await file.exists()) {
        if (kDebugMode) {
          print(
            'LocalTracksNotifier: Could not delete physical file: ${track.localFilePath}',
          );
        }
        return false;
      }

      // Delete legacy .cover.jpg if present
      try {
        final legacyCover = File('${track.localFilePath}.cover.jpg');
        if (await legacyCover.exists()) {
          await legacyCover.delete();
        }
      } catch (_) {}

      // Evict artwork cache
      LocalArtworkService.evict(track.localFilePath!);
    }

    // 2. Only remove from state and Hive once disk deletion has succeeded (or wasn't requested)
    state = state.where((t) => t.id != track.id).toList();
    try {
      await HiveService.localMusicTracksBox.delete(track.id);
    } catch (e) {
      if (kDebugMode) {
        print('LocalTracksNotifier: Hive delete error: $e');
      }
    }

    // If it's also a downloaded track in Hive, delete from DownloadService/Hive
    try {
      if (Hive.isBoxOpen('music_downloads')) {
        final box = Hive.box<DownloadEntity>('music_downloads');
        final matchingKeys = <dynamic>[];
        for (final entry in box.toMap().entries) {
          if (entry.value.trackId == track.id ||
              (track.localFilePath != null &&
                  _normalizePath(entry.value.localPath).toLowerCase() ==
                      _normalizePath(track.localFilePath!).toLowerCase())) {
            matchingKeys.add(entry.key);
          }
        }
        if (matchingKeys.isNotEmpty) {
          await box.deleteAll(matchingKeys);
        }
      }
    } catch (_) {}

    return true;
  }

  void removeTracksInFolder(String folderPath) {
    final normalizedFolder = _normalizePath(folderPath);
    final folderWithSep = '$normalizedFolder/';

    final removedIds = <String>[];
    final remaining = <Track>[];

    for (final track in state) {
      final filePath = track.localFilePath;
      if (filePath == null || filePath.isEmpty) {
        remaining.add(track);
        continue;
      }

      final normalizedFile = _normalizePath(filePath);
      final isInFolder =
          normalizedFile == normalizedFolder ||
          normalizedFile.startsWith(folderWithSep);

      if (isInFolder) {
        removedIds.add(track.id);
      } else {
        remaining.add(track);
      }
    }

    if (removedIds.isEmpty) return;

    state = remaining;
    HiveService.localMusicTracksBox.deleteAll(removedIds);
  }

  Future<void> _persistNewTracks(List<Track> tracks) async {
    try {
      final box = HiveService.localMusicTracksBox;
      final entities = {for (final t in tracks) t.id: _trackToEntity(t)};
      await box.putAll(entities);
    } catch (e) {
      if (kDebugMode) {
        print('LocalTracksNotifier: Persist error: $e');
      }
    }
  }
}

/// Local music scanner service
class LocalMusicScanner {
  static const _audioExtensions = [
    '.mp3',
    '.m4a',
    '.flac',
    '.wav',
    '.ogg',
    '.aac',
    '.opus',
  ];

  /// Request storage permission
  /// Returns: 'granted', 'denied', or 'permanentlyDenied'
  static Future<String> requestPermissionWithStatus() async {
    if (Platform.isAndroid) {
      // Check if already granted
      final audioStatus = await Permission.audio.status;
      if (audioStatus.isGranted) return 'granted';

      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return 'granted';

      // Check if permanently denied (user selected "Don't ask again")
      if (audioStatus.isPermanentlyDenied ||
          storageStatus.isPermanentlyDenied) {
        return 'permanentlyDenied';
      }

      // Try requesting audio permission first (Android 13+)
      final audioRequest = await Permission.audio.request();
      if (audioRequest.isGranted) return 'granted';
      if (audioRequest.isPermanentlyDenied) return 'permanentlyDenied';

      // Fall back to storage permission for older Android
      final storageRequest = await Permission.storage.request();
      if (storageRequest.isGranted) return 'granted';
      if (storageRequest.isPermanentlyDenied) return 'permanentlyDenied';

      // Try manage external storage for Android 11+
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return 'granted';
      if (manageStatus.isPermanentlyDenied) return 'permanentlyDenied';

      // If we get here, permission was denied but not permanently
      // However on Android, after first denial, system won't show dialog again
      // So we treat any denial as needing settings
      return 'permanentlyDenied';
    }
    return 'granted'; // iOS/Desktop don't need explicit permission
  }

  /// Simple permission check (for backward compatibility)
  static Future<bool> requestPermission() async {
    final status = await requestPermissionWithStatus();
    return status == 'granted';
  }

  /// Open app settings
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Check if the app has permission to delete files from external/device storage
  static Future<bool> hasDeleteStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Check manageExternalStorage first (Android 11+ / API 30+)
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Fall back to storage permission for older Android (API <= 29)
    if (await Permission.storage.isGranted) {
      return true;
    }

    return false;
  }

  /// Request permission to delete files from external/device storage
  static Future<bool> requestDeleteStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Request manageExternalStorage for Android 11+
    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

    // Fall back to storage permission for older Android (API <= 29)
    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  /// Pick a folder to add
  static Future<String?> pickFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('Error picking folder: $e');
      }
      return null;
    }
  }

  /// Scan a directory for audio files
  /// File discovery runs in a background isolate.
  /// Track metadata parsing runs in chunked background isolates with UI yielding
  /// so large libraries (1,000+ FLACs) never freeze the UI or trigger ANR/LMK kills.
  static Future<List<Track>> scanDirectory(
    String path, {
    void Function(int scanned, int total, String current)? onProgress,
  }) async {
    final directory = Directory(path);

    if (!await directory.exists()) {
      return [];
    }

    // Build download lookup map on main thread (Hive is fast)
    final downloadLookup = await _buildDownloadLookup();

    // Discover audio files in background isolate
    final filePaths = await compute(
      _discoverAudioFilesIsolate,
      _ScanRequest(path: path, extensions: _audioExtensions),
    );

    if (filePaths.isEmpty) return [];

    final tracks = <Track>[];
    const batchSize = 50;

    for (int i = 0; i < filePaths.length; i += batchSize) {
      final batch = filePaths.sublist(i, min(i + batchSize, filePaths.length));
      final batchTracks = await compute(
        _processBatchIsolate,
        _BatchScanRequest(
          filePaths: batch,
          downloadLookup: downloadLookup,
        ),
      );
      tracks.addAll(batchTracks);

      final currentFile = batch.isNotEmpty ? batch.last : '';
      onProgress?.call(
        min(i + batch.length, filePaths.length),
        filePaths.length,
        currentFile,
      );

      // Yield to the Flutter UI event loop so frame rendering, snackbars,
      // and Android's main looper stay 100% smooth.
      await Future.delayed(Duration.zero);
    }

    return tracks;
  }

  /// Build a lookup map of downloaded tracks by file path
  static Future<Map<String, _DownloadLookupItem>> _buildDownloadLookup() async {
    try {
      if (!Hive.isBoxOpen('music_downloads')) {
        await Hive.openBox<DownloadEntity>('music_downloads');
      }
      final box = Hive.box<DownloadEntity>('music_downloads');
      final map = <String, _DownloadLookupItem>{};
      for (final e in box.values) {
        final item = _DownloadLookupItem(
          trackId: e.trackId,
          title: e.title,
          artist: e.artist,
          album: e.album,
          durationMs: e.durationMs,
          thumbnailUrl: e.thumbnailUrl,
        );
        map[e.localPath] = item;
        map[_normalizePath(e.localPath).toLowerCase()] = item;
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  /// Scan all registered folders
  static Future<List<Track>> scanAllFolders(
    List<String> folders, {
    void Function(int scanned, int total, String current)? onProgress,
  }) async {
    final allTracks = <Track>[];

    for (final folder in folders) {
      final tracks = await scanDirectory(folder, onProgress: onProgress);
      allTracks.addAll(tracks);
    }

    return allTracks;
  }
}

TrackEntity _trackToEntity(Track track) {
  return TrackEntity(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration.inMilliseconds,
    thumbnailUrl: track.thumbnailUrl,
    isExplicit: track.isExplicit,
    isLiked: track.isLiked,
    addedAt: track.addedAt,
    localFilePath: track.localFilePath,
  );
}

Track _trackFromEntity(TrackEntity entity) {
  return Track(
    id: entity.id,
    title: entity.title,
    artist: entity.artist,
    album: entity.album,
    duration: Duration(milliseconds: entity.duration),
    thumbnailUrl: entity.thumbnailUrl,
    isExplicit: entity.isExplicit,
    isLiked: entity.isLiked,
    addedAt: entity.addedAt,
    localFilePath: entity.localFilePath,
  );
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
}

/// Request data for isolate file discovery
class _ScanRequest {
  final String path;
  final List<String> extensions;

  _ScanRequest({required this.path, required this.extensions});
}

/// Top-level function for compute() - discovers audio files in a directory
/// Must be top-level to work with compute()
List<String> _discoverAudioFilesIsolate(_ScanRequest request) {
  final filePaths = <String>[];
  final directory = Directory(request.path);

  try {
    // Synchronous recursive listing (runs in isolate, won't block UI)
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (request.extensions.any((e) => ext.endsWith(e))) {
          filePaths.add(entity.path);
        }
      }
    }
  } catch (e) {
    // Silently handle permission errors for inaccessible directories
  }

  return filePaths;
}

/// Isolate-safe representation of downloaded track metadata
class _DownloadLookupItem {
  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? thumbnailUrl;

  const _DownloadLookupItem({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.thumbnailUrl,
  });
}

/// Request data for isolate chunk processing
class _BatchScanRequest {
  final List<String> filePaths;
  final Map<String, _DownloadLookupItem> downloadLookup;

  _BatchScanRequest({
    required this.filePaths,
    required this.downloadLookup,
  });
}

/// Top-level function for compute() - parses a batch of audio files in a background isolate
List<Track> _processBatchIsolate(_BatchScanRequest request) {
  final tracks = <Track>[];

  for (final filePath in request.filePaths) {
    try {
      final track = _fileToTrack(filePath, request.downloadLookup);
      if (track != null) {
        tracks.add(track);
      }
    } catch (e) {
      // Safe fallback on unexpected error
      try {
        final fallback = SafeAudioMetadataReader.parseFilenameFallback(filePath);
        tracks.add(
          Track(
            id: 'local_${filePath.hashCode}',
            title: fallback.title ?? 'Unknown Track',
            artist: fallback.artist ?? 'Unknown Artist',
            album: fallback.album,
            duration: fallback.duration ?? const Duration(minutes: 3),
            thumbnailUrl: null,
            localFilePath: filePath,
          ),
        );
      } catch (_) {}
    }
  }

  return tracks;
}

Track? _fileToTrack(
  String filePath,
  Map<String, _DownloadLookupItem> downloadLookup,
) {
  try {
    // Check if this file is a known download (by exact path or normalized lowercase)
    final entity = downloadLookup[filePath] ??
        downloadLookup[_normalizePath(filePath).toLowerCase()];
    if (entity != null) {
      return Track(
        id: entity.trackId,
        title: entity.title,
        artist: entity.artist,
        album: entity.album,
        duration: Duration(milliseconds: entity.durationMs),
        thumbnailUrl: entity.thumbnailUrl,
        localFilePath: filePath,
      );
    }

    // Try reading metadata safely
    final audioFile = File(filePath);
    final meta = SafeAudioMetadataReader.readMetadata(audioFile, extractPicture: false);

    String title = meta.title ?? '';
    String artist = meta.artist ?? '';

    if (title.isEmpty || artist.isEmpty) {
      final fallback = SafeAudioMetadataReader.parseFilenameFallback(filePath);
      if (title.isEmpty) title = fallback.title ?? 'Unknown Track';
      if (artist.isEmpty) artist = fallback.artist ?? 'Unknown Artist';
    }

    final id = 'local_${filePath.hashCode}';

    return Track(
      id: id,
      title: title,
      artist: artist,
      album: meta.album,
      duration: meta.duration ?? const Duration(minutes: 3),
      thumbnailUrl: null,
      localFilePath: filePath,
    );
  } catch (_) {
    final fallback = SafeAudioMetadataReader.parseFilenameFallback(filePath);
    return Track(
      id: 'local_${filePath.hashCode}',
      title: fallback.title ?? 'Unknown Track',
      artist: fallback.artist ?? 'Unknown Artist',
      album: fallback.album,
      duration: fallback.duration ?? const Duration(minutes: 3),
      thumbnailUrl: null,
      localFilePath: filePath,
    );
  }
}
