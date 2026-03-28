import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/design_system/design_system.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/cache/hive_service.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/providers.dart'
    hide searchHistoryProvider, recentlyPlayedProvider;
import '../../models/models.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/playback/playback_data.dart';
import '../services/queue_persistence_service.dart';

const Set<String> _backupSettingsKeys = <String>{
  ThemeModeNotifier.themeModePrefKey,
  kStreamingQualityKey,
  kStreamCacheWifiOnlyKey,
  kStreamCacheSizeLimitMbKey,
  kStreamCacheMaxConcurrentKey,
  kCrossfadeDurationMsKey,
  kDownloadQualityKey,
  kDownloadParallelPartCountKey,
  kDownloadParallelMinSizeMbKey,
};

/// Backup and restore screen
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;

    // Dynamic colors - plain white background in light mode
    final backgroundColor = (hasAlbumColors && isDark)
        ? albumColors.backgroundSecondary
        : (isDark ? InzxColors.darkBackground : InzxColors.background);
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(l10n.backupRestoreTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Iconsax.info_circle, color: accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.backupIncludesDescription,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : InzxColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Backup section
          Text(
            l10n.createBackup,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            isDark: isDark,
            icon: Iconsax.export_1,
            title: l10n.exportBackup,
            subtitle: l10n.exportBackupSubtitle,
            isLoading: _isBackingUp,
            onTap: _createBackup,
          ),

          const SizedBox(height: 24),

          // Restore section
          Text(
            l10n.restoreBackup,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            isDark: isDark,
            icon: Iconsax.import_1,
            title: l10n.importBackup,
            subtitle: l10n.importBackupSubtitle,
            isLoading: _isRestoring,
            onTap: _restoreBackup,
          ),

          const SizedBox(height: 32),

          // Danger zone
          Text(
            l10n.dangerZone,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            isDark: isDark,
            icon: Iconsax.trash,
            title: l10n.clearAppData,
            subtitle: l10n.clearAppDataSubtitle,
            color: Colors.red,
            onTap: _clearAllData,
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isLoading = false,
    Color? color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                color?.withValues(alpha: 0.3) ??
                (isDark ? Colors.white12 : Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (color ?? Theme.of(context).colorScheme.primary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      icon,
                      color: color ?? Theme.of(context).colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          color ??
                          (isDark ? Colors.white : InzxColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : InzxColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white24 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    final l10n = context.l10n;

    try {
      final backup = await _generateBackupData();
      final json = await compute(_encodeBackupIsolate, backup);

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().split('T')[0];
      final file = File('${tempDir.path}/inzx_backup_$timestamp.json');
      await file.writeAsString(json);

      // Share
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: l10n.backupSubject),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.backupCreatedSuccessfully)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.backupFailed('$e'))));
      }
    }

    setState(() => _isBackingUp = false);
  }

  Future<void> _restoreBackup() async {
    setState(() => _isRestoring = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isRestoring = false);
        return;
      }

      final file = File(result.files.single.path!);
      final json = await file.readAsString();
      final backup = await compute(_parseBackupIsolate, json);

      await _restoreFromBackup(backup);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupRestoredSuccessfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.restoreFailed('$e'))),
        );
      }
    }

    setState(() => _isRestoring = false);
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearAllDataQuestion),
        content: Text(context.l10n.clearAllDataWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.clearAll),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final playerService = ref.read(audioPlayerServiceProvider);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await QueuePersistenceService.clearQueue();

      // Clear non-download local cache/storage in Hive.
      await HiveService.tracksBox.clear();
      await HiveService.searchCacheBox.clear();
      await HiveService.playbackBox.clear();
      await HiveService.metadataBox.clear();
      await HiveService.lyricsBox.clear();
      await HiveService.homePageBox.clear();
      await HiveService.albumsBox.clear();
      await HiveService.artistsBox.clear();
      await HiveService.playlistsBox.clear();
      await HiveService.colorsBox.clear();
      await HiveService.streamCacheBox.clear();
      await HiveService.localMusicFoldersBox.clear();
      await HiveService.localMusicTracksBox.clear();

      // Keep downloaded files untouched, but clear stream byte-cache files.
      await playerService.clearStreamAudioCache();

      // Reset in-memory app state.
      ref.read(likedSongsProvider.notifier).replaceAll(const []);
      ref.read(localPlaylistsProvider.notifier).replaceAll(const []);
      await ref.read(searchHistoryProvider.notifier).clearHistory();
      await ref.read(recentlyPlayedProvider.notifier).clearHistory();
      ref.invalidate(ytMusicLikedSongsProvider);
      ref.invalidate(ytMusicSavedAlbumsProvider);
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      ref.invalidate(ytMusicSubscribedArtistsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.appDataClearedPreserved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.failedGeneric('$e'))),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _generateBackupData() async {
    // Collect all data
    final likedSongs = ref.read(likedSongsProvider);
    final playlists = ref.read(localPlaylistsProvider);
    final searchHistory = ref.read(searchHistoryProvider);
    final recentlyPlayed = ref.read(recentlyPlayedProvider);
    final prefs = await SharedPreferences.getInstance();

    final settings = <String, dynamic>{};
    for (final key in _backupSettingsKeys) {
      if (!prefs.containsKey(key)) continue;
      settings[key] = prefs.get(key);
    }

    return {
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'liked_songs': likedSongs.map((t) => t.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'search_history': searchHistory,
      'recently_played': recentlyPlayed.map((t) => t.toJson()).toList(),
      'settings': settings,
    };
  }

  Future<void> _restoreFromBackup(Map<String, dynamic> backup) async {
    // Restore liked songs
    if (backup['liked_songs'] != null) {
      final songs = (backup['liked_songs'] as List)
          .map((json) => Track.fromJson(json))
          .toList();
      ref.read(likedSongsProvider.notifier).replaceAll(songs);
    }

    // Restore playlists
    if (backup['playlists'] != null) {
      final playlists = (backup['playlists'] as List)
          .map((json) => Playlist.fromJson(json))
          .toList();
      ref.read(localPlaylistsProvider.notifier).replaceAll(playlists);
    }

    // Restore search history
    if (backup['search_history'] != null) {
      await ref.read(searchHistoryProvider.notifier).clearHistory();
      for (final query in (backup['search_history'] as List).reversed) {
        await ref.read(searchHistoryProvider.notifier).addSearch(query);
      }
    }

    // Restore recently played
    if (backup['recently_played'] != null) {
      await ref.read(recentlyPlayedProvider.notifier).clearHistory();
      final tracks = (backup['recently_played'] as List)
          .map((json) => Track.fromJson(json))
          .toList();
      for (final track in tracks.reversed) {
        await ref.read(recentlyPlayedProvider.notifier).addTrack(track);
      }
    }

    final settingsRaw = backup['settings'];
    if (settingsRaw is Map) {
      await _restoreSettings(Map<String, dynamic>.from(settingsRaw));
    }
  }

  Future<void> _restoreSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();

    for (final entry in settings.entries) {
      if (!_backupSettingsKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is List && value.every((v) => v is String)) {
        await prefs.setStringList(entry.key, value.cast<String>());
      }
    }

    if (settings.containsKey(ThemeModeNotifier.themeModePrefKey)) {
      final themeIndex = settings[ThemeModeNotifier.themeModePrefKey];
      if (themeIndex is int &&
          themeIndex >= 0 &&
          themeIndex < InzxThemeMode.values.length) {
        ref
            .read(themeModeProvider.notifier)
            .setThemeMode(InzxThemeMode.values[themeIndex]);
      }
    }

    final playerService = ref.read(audioPlayerServiceProvider);
    final streamingQuality = settings[kStreamingQualityKey];
    if (streamingQuality is int &&
        streamingQuality >= 0 &&
        streamingQuality < AudioQuality.values.length) {
      playerService.setAudioQuality(AudioQuality.values[streamingQuality]);
    }

    final cacheWifiOnly = settings[kStreamCacheWifiOnlyKey];
    if (cacheWifiOnly is bool) {
      await playerService.setStreamCacheWifiOnly(cacheWifiOnly);
    }

    final cacheLimit = settings[kStreamCacheSizeLimitMbKey];
    if (cacheLimit is int) {
      await playerService.setStreamCacheSizeLimitMb(cacheLimit);
    }

    final cacheConcurrent = settings[kStreamCacheMaxConcurrentKey];
    if (cacheConcurrent is int) {
      await playerService.setStreamCacheMaxConcurrent(cacheConcurrent);
    }

    final crossfadeMs = settings[kCrossfadeDurationMsKey];
    if (crossfadeMs is int) {
      await playerService.setCrossfadeDurationMs(crossfadeMs);
    }

    final downloadQualityIndex = settings[kDownloadQualityKey];
    if (downloadQualityIndex is int &&
        downloadQualityIndex >= 0 &&
        downloadQualityIndex < AudioQuality.values.length) {
      final quality = AudioQuality.values[downloadQualityIndex];
      await ref.read(downloadQualityProvider.notifier).setQuality(quality);
      ref.read(downloadManagerProvider.notifier).setDownloadQuality(quality);
    }
  }
}

/// Top-level function for isolate - parses backup JSON
Map<String, dynamic> _parseBackupIsolate(String json) {
  return jsonDecode(json) as Map<String, dynamic>;
}

/// Top-level function for isolate - encodes backup to JSON
String _encodeBackupIsolate(Map<String, dynamic> backup) {
  return jsonEncode(backup);
}
