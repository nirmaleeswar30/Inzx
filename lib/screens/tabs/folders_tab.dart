import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/local_music_scanner.dart';
import '../widgets/track_options_sheet.dart';

/// Folders tab for local file browsing (placeholder)
class MusicFoldersTab extends ConsumerStatefulWidget {
  const MusicFoldersTab({super.key});

  @override
  ConsumerState<MusicFoldersTab> createState() => _MusicFoldersTabState();
}

class _MusicFoldersTabState extends ConsumerState<MusicFoldersTab> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        children: [
          // Header
          _buildHeader(isDark, colorScheme),

          // Content
          Expanded(child: _buildContent(isDark, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Folders',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  _showScanDialog();
                },
                icon: Icon(
                  Icons.document_scanner_rounded,
                  color: isDark ? Colors.white70 : MineColors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () {
                  _showSettingsDialog();
                },
                icon: Icon(
                  Icons.settings_rounded,
                  color: isDark ? Colors.white70 : MineColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folders = ref.read(localMusicFoldersProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Folder Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (folders.isEmpty)
              Text(
                'No folders added yet',
                style: TextStyle(
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              )
            else
              ...folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(
                    folder.split('/').last,
                    style: TextStyle(
                      color: isDark ? Colors.white : MineColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    folder,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade300,
                    ),
                    onPressed: () {
                      ref
                          .read(localMusicFoldersProvider.notifier)
                          .removeFolder(folder);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _pickFolder();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Folder'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: folders.isEmpty
                        ? null
                        : () {
                            Navigator.pop(context);
                            ref.read(localTracksProvider.notifier).clear();
                            ref
                                .read(localMusicFoldersProvider.notifier)
                                .clear();
                          },
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('Clear All'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, ColorScheme colorScheme) {
    final localTracks = ref.watch(localTracksProvider);
    final folders = ref.watch(localMusicFoldersProvider);

    // If we have scanned tracks, show them
    if (localTracks.isNotEmpty) {
      return _buildTrackList(localTracks, folders, isDark, colorScheme);
    }

    // Otherwise show placeholder
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white10
                    : colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 56,
                color: isDark
                    ? Colors.white38
                    : colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Local Music',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan your device to find local music files and play them offline',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white54 : MineColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _showScanDialog,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Scan for music'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: const Text('Add folder'),
            ),
            const SizedBox(height: 48),
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: isDark ? Colors.white38 : MineColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Supported formats: MP3, FLAC, WAV, M4A, OGG',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white54
                            : MineColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList(
    List<Track> tracks,
    List<String> folders,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final playerService = ref.watch(audioPlayerServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${tracks.length} songs from ${folders.length} folder(s)',
                style: TextStyle(
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
              TextButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),

        // Track list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  onPressed: () => TrackOptionsSheet.show(context, track),
                ),
                onTap: () => playerService.playQueue(tracks, startIndex: index),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pickFolder() async {
    // Request permission first with detailed status
    final permissionStatus =
        await LocalMusicScanner.requestPermissionWithStatus();

    if (permissionStatus == 'denied') {
      if (mounted) {
        _showPermissionDialog(isPermanentlyDenied: false);
      }
      return;
    }

    if (permissionStatus == 'permanentlyDenied') {
      if (mounted) {
        _showPermissionDialog(isPermanentlyDenied: true);
      }
      return;
    }

    final folderPath = await LocalMusicScanner.pickFolder();
    if (folderPath != null && mounted) {
      ref.read(localMusicFoldersProvider.notifier).addFolder(folderPath);
      // Ask if user wants to scan immediately
      _showScanNewFolderDialog(folderPath);
    }
  }

  void _showPermissionDialog({bool isPermanentlyDenied = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            Icon(Icons.folder_off_rounded, color: Colors.orange.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Permission Required',
                style: TextStyle(
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Storage permission is required to access your music files. Please enable it in Settings.',
          style: TextStyle(
            color: isDark ? Colors.white70 : MineColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              // Always open settings since Android won't re-show permission dialog
              final opened = await LocalMusicScanner.openSettings();
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open settings. Please enable storage permission manually.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showScanNewFolderDialog(String folderPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folderName = folderPath.split('/').last;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          'Folder Added',
          style: TextStyle(
            color: isDark ? Colors.white : MineColors.textPrimary,
          ),
        ),
        content: Text(
          'Added "$folderName". Would you like to scan it for music now?',
          style: TextStyle(
            color: isDark ? Colors.white70 : MineColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _scanFolder(folderPath);
            },
            child: const Text('Scan Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanFolder(String path) async {
    _showScanningProgress();

    final tracks = await LocalMusicScanner.scanDirectory(
      path,
      onProgress: (scanned, total, current) {
        ref.read(scanProgressProvider.notifier).state = ScanProgress(
          scannedFiles: scanned,
          totalFiles: total,
          currentFile: current,
        );
      },
    );

    if (mounted) {
      Navigator.of(context).pop(); // Close progress dialog
      ref.read(localTracksProvider.notifier).addTracks(tracks);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Found ${tracks.length} songs')));
    }
  }

  void _showScanDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folders = ref.read(localMusicFoldersProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.document_scanner_rounded,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
            const SizedBox(width: 12),
            Text(
              'Scan for music',
              style: TextStyle(
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folders.isEmpty
                  ? 'Add a folder first, then scan for audio files.'
                  : 'This will scan ${folders.length} folder(s) for audio files.',
              style: TextStyle(
                color: isDark ? Colors.white70 : MineColors.textSecondary,
              ),
            ),
            if (folders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Folders to scan:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              ...folders
                  .take(3)
                  .map(
                    (f) => Text(
                      '• ${f.split('/').last}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : MineColors.textSecondary,
                      ),
                    ),
                  ),
              if (folders.length > 3)
                Text(
                  '... and ${folders.length - 3} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : MineColors.textSecondary,
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (folders.isEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _pickFolder();
              },
              child: const Text('Add Folder'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _startScanning();
              },
              child: const Text('Start Scan'),
            ),
        ],
      ),
    );
  }

  Future<void> _startScanning() async {
    final folders = ref.read(localMusicFoldersProvider);
    if (folders.isEmpty) return;

    _showScanningProgress();

    final allTracks = <Track>[];
    for (final folder in folders) {
      final tracks = await LocalMusicScanner.scanDirectory(
        folder,
        onProgress: (scanned, total, current) {
          ref.read(scanProgressProvider.notifier).state = ScanProgress(
            scannedFiles: scanned,
            totalFiles: total,
            currentFile: current,
          );
        },
      );
      allTracks.addAll(tracks);
    }

    if (mounted) {
      Navigator.of(context).pop(); // Close progress dialog
      ref.read(localTracksProvider.notifier).addTracks(allTracks);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Found ${allTracks.length} songs in ${folders.length} folder(s)',
          ),
        ),
      );
    }
  }

  void _showScanningProgress() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final progress = ref.watch(scanProgressProvider);
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(value: progress?.progress),
                const SizedBox(height: 24),
                Text(
                  'Scanning for music...',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : MineColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (progress != null) ...[
                  Text(
                    '${progress.scannedFiles} / ${progress.totalFiles} files',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    progress.currentFile.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
