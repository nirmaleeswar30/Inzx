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
import '../../core/design_system/design_system.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/providers.dart'
    hide searchHistoryProvider, recentlyPlayedProvider;
import '../../models/models.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: const Text('Backup & Restore'),
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
              color: colorScheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Iconsax.info_circle, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backup includes liked songs, playlists, search history, and settings.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : MineColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Backup section
          Text(
            'Create Backup',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            isDark: isDark,
            icon: Iconsax.export_1,
            title: 'Export Backup',
            subtitle: 'Save a backup file to share or store',
            isLoading: _isBackingUp,
            onTap: _createBackup,
          ),

          const SizedBox(height: 24),

          // Restore section
          Text(
            'Restore Backup',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            isDark: isDark,
            icon: Iconsax.import_1,
            title: 'Import Backup',
            subtitle: 'Restore from a backup file',
            isLoading: _isRestoring,
            onTap: _restoreBackup,
          ),

          const SizedBox(height: 32),

          // Danger zone
          Text(
            'Danger Zone',
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
            title: 'Clear All Data',
            subtitle: 'Remove all local data and settings',
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
                          (isDark ? Colors.white : MineColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
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

    try {
      final backup = await _generateBackupData();
      final json = await compute(_encodeBackupIsolate, backup);

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().split('T')[0];
      final file = File('${tempDir.path}/mine_backup_$timestamp.json');
      await file.writeAsString(json);

      // Share
      await Share.shareXFiles([XFile(file.path)], subject: 'Mine Music Backup');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
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
          const SnackBar(content: Text('Backup restored successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }

    setState(() => _isRestoring = false);
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will remove all liked songs, playlists, search history, and settings. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Clear providers
      ref.invalidate(likedSongsProvider);
      ref.invalidate(localPlaylistsProvider);
      ref.invalidate(searchHistoryProvider);
      ref.invalidate(recentlyPlayedProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All data cleared')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<Map<String, dynamic>> _generateBackupData() async {
    // Collect all data
    final likedSongs = ref.read(likedSongsProvider);
    final playlists = ref.read(localPlaylistsProvider);
    final searchHistory = ref.read(searchHistoryProvider);
    final recentlyPlayed = ref.read(recentlyPlayedProvider);

    return {
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'liked_songs': likedSongs.map((t) => t.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'search_history': searchHistory,
      'recently_played': recentlyPlayed.map((t) => t.toJson()).toList(),
      'settings': {
        // Add any settings you want to backup
      },
    };
  }

  Future<void> _restoreFromBackup(Map<String, dynamic> backup) async {
    // Restore liked songs
    if (backup['liked_songs'] != null) {
      final songs = (backup['liked_songs'] as List)
          .map((json) => Track.fromJson(json))
          .toList();
      for (final song in songs) {
        ref.read(likedSongsProvider.notifier).toggleLike(song);
      }
    }

    // Restore playlists
    if (backup['playlists'] != null) {
      // TODO: Add restore method to playlist provider
      // final playlists = (backup['playlists'] as List)
      //     .map((json) => Playlist.fromJson(json))
      //     .toList();
    }

    // Restore search history
    if (backup['search_history'] != null) {
      for (final query in (backup['search_history'] as List).reversed) {
        ref.read(searchHistoryProvider.notifier).addSearch(query);
      }
    }

    // Restore recently played
    if (backup['recently_played'] != null) {
      final tracks = (backup['recently_played'] as List)
          .map((json) => Track.fromJson(json))
          .toList();
      for (final track in tracks.reversed) {
        ref.read(recentlyPlayedProvider.notifier).addTrack(track);
      }
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
