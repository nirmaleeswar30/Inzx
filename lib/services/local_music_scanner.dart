import 'dart:io';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import '../models/models.dart';
import '../data/entities/download_entity.dart';

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
  LocalMusicFoldersNotifier() : super([]);

  void addFolder(String path) {
    if (!state.contains(path)) {
      state = [...state, path];
    }
  }

  void removeFolder(String path) {
    state = state.where((p) => p != path).toList();
  }

  void clear() {
    state = [];
  }
}

/// Local tracks notifier
class LocalTracksNotifier extends StateNotifier<List<Track>> {
  LocalTracksNotifier() : super([]);

  void addTracks(List<Track> tracks) {
    final existingIds = state.map((t) => t.id).toSet();
    final newTracks = tracks.where((t) => !existingIds.contains(t.id)).toList();
    state = [...state, ...newTracks];
  }

  void clear() {
    state = [];
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

  /// Pick a folder to add
  static Future<String?> pickFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      return result;
    } catch (e) {
      if (kDebugMode) {print('Error picking folder: $e');}
      return null;
    }
  }

  /// Scan a directory for audio files
  /// File discovery runs in a background isolate to avoid UI jank
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

    // Process files on main thread (needed for progress callback)
    for (int i = 0; i < filePaths.length; i++) {
      final filePath = filePaths[i];
      onProgress?.call(i + 1, filePaths.length, filePath);

      try {
        final track = _fileToTrackSync(filePath, downloadLookup);
        if (track != null) {
          tracks.add(track);
        }
      } catch (e) {
        if (kDebugMode) {print('Error processing file $filePath: $e');}
      }
    }

    return tracks;
  }

  /// Build a lookup map of downloaded tracks by file path
  static Future<Map<String, DownloadEntity>> _buildDownloadLookup() async {
    try {
      if (!Hive.isBoxOpen('downloads')) {
        await Hive.openBox<DownloadEntity>('downloads');
      }
      final box = Hive.box<DownloadEntity>('downloads');
      return {for (final e in box.values) e.localPath: e};
    } catch (e) {
      return {};
    }
  }

  /// Convert a file path to a Track (synchronous, uses pre-built lookup)
  static Track? _fileToTrackSync(
    String filePath,
    Map<String, DownloadEntity> downloadLookup,
  ) {
    try {
      // Check if this file is a known download
      final entity = downloadLookup[filePath];
      if (entity != null) {
        return Track(
          id: entity.trackId,
          title: entity.title,
          artist: entity.artist,
          duration: Duration(milliseconds: entity.durationMs),
          thumbnailUrl: entity.thumbnailUrl,
          localFilePath: filePath,
        );
      }

      // Fall back to parsing filename
      final fileName = filePath.split(Platform.pathSeparator).last;
      final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

      String title;
      String artist;

      if (nameWithoutExt.contains(' - ')) {
        final parts = nameWithoutExt.split(' - ');
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      } else {
        title = nameWithoutExt;
        artist = 'Unknown Artist';
      }

      final id = 'local_${filePath.hashCode}';

      return Track(
        id: id,
        title: title,
        artist: artist,
        duration: const Duration(minutes: 3),
        thumbnailUrl: null,
        localFilePath: filePath,
      );
    } catch (e) {
      return null;
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
