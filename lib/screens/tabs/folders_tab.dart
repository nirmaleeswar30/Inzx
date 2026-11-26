import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/utils/platform_utils.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/local_music_scanner.dart';
import '../../services/download_service.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_artwork_view.dart';

/// Folders tab for local file browsing
class MusicFoldersTab extends ConsumerStatefulWidget {
  const MusicFoldersTab({super.key});

  @override
  ConsumerState<MusicFoldersTab> createState() => _MusicFoldersTabState();
}

class _MusicFoldersTabState extends ConsumerState<MusicFoldersTab> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localTracksProvider.notifier).pruneMissingFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
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
    final l10n = context.l10n;
    final accentColor = ref.watch(effectiveAccentColorProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.folders,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: l10n.scanForMusic,
                onPressed: _isSyncing ? null : _syncFoldersAutomatically,
                icon: _isSyncing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      )
                    : Icon(
                        Icons.sync_rounded,
                        color: isDark ? Colors.white70 : InzxColors.textPrimary,
                      ),
              ),
              IconButton(
                tooltip: l10n.folderSettings,
                onPressed: _showSettingsDialog,
                icon: Icon(
                  Icons.settings_rounded,
                  color: isDark ? Colors.white70 : InzxColors.textPrimary,
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
    final textColor = isDark ? Colors.white : InzxColors.textPrimary;
    final secondaryColor = isDark ? Colors.white70 : InzxColors.textSecondary;
    final sheetBg = isDark
        ? const Color(0xFF141414).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.95);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return Consumer(
          builder: (context, ref, child) {
            final l10n = context.l10n;
            final folders = ref.watch(localMusicFoldersProvider);
            final liveAccent = ref.watch(effectiveAccentColorProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    enabled: !isDesktop,
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: modalSheetBackground(context, sheetBg),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: liveAccent.withValues(alpha: 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Drag handle
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // Section Title & Badge
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    l10n.folderSettings,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  if (folders.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: liveAccent.withValues(
                                          alpha: isDark ? 0.25 : 0.15,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${folders.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: liveAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Folders list
                            if (folders.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    l10n.noFoldersAddedYet,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: secondaryColor,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.of(context).size.height * 0.42,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: folders.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final folder = folders[index];
                                    final folderName = folder.split('/').last;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: (isDark
                                                ? Colors.white
                                                : Colors.black)
                                            .withValues(
                                          alpha: isDark ? 0.05 : 0.04,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(
                                            alpha: isDark ? 0.08 : 0.06,
                                          ),
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 2,
                                        ),
                                        leading: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: liveAccent.withValues(
                                              alpha: isDark ? 0.2 : 0.12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.folder_rounded,
                                            color: liveAccent,
                                            size: 20,
                                          ),
                                        ),
                                        title: Text(
                                          folderName.isEmpty
                                              ? folder
                                              : folderName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: textColor,
                                          ),
                                        ),
                                        subtitle: Text(
                                          folder,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: secondaryColor,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.red.shade400,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            ref
                                                .read(
                                                  localTracksProvider.notifier,
                                                )
                                                .removeTracksInFolder(folder);
                                            ref
                                                .read(
                                                  localMusicFoldersProvider
                                                      .notifier,
                                                )
                                                .removeFolder(folder);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(bottomSheetContext);
                                      _pickFolder();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: liveAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      l10n.addFolder,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (folders.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(bottomSheetContext);
                                      ref
                                          .read(localTracksProvider.notifier)
                                          .clear();
                                      ref
                                          .read(
                                            localMusicFoldersProvider.notifier,
                                          )
                                          .clear();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade400,
                                      side: BorderSide(
                                        color: Colors.red.shade400.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_sweep_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l10n.clearAll),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContent(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final localTracks = ref.watch(localTracksProvider);
    final folders = ref.watch(localMusicFoldersProvider);
    final accentColor = ref.watch(effectiveAccentColorProvider);

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
                color: accentColor.withValues(alpha: isDark ? 0.16 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 56,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.localMusic,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : InzxColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.scanLocalMusicDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isSyncing ? null : _syncFoldersAutomatically,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(l10n.scanForMusic),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: Text(l10n.addFolderLowercase),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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
                    color: isDark ? Colors.white38 : InzxColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.supportedFormats,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white54
                            : InzxColors.textSecondary,
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
    final l10n = context.l10n;
    final playerService = ref.watch(audioPlayerServiceProvider);
    final accentColor = ref.watch(effectiveAccentColorProvider);

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
                l10n.songsFromFoldersCount(tracks.length, folders.length),
                style: TextStyle(
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
              ),
              TextButton.icon(
                onPressed: _pickFolder,
                style: TextButton.styleFrom(
                  foregroundColor: accentColor,
                ),
                icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                label: Text(l10n.add),
              ),
            ],
          ),
        ),

        // Track list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 160),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return Dismissible(
                key: ValueKey('folder_track_${track.id}_${track.localFilePath ?? ''}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red.shade700,
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                confirmDismiss: (_) => _confirmDeleteTrack(track),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                  leading: TrackArtworkView(
                    track: track,
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                    fallbackColor: accentColor.withValues(
                      alpha: isDark ? 0.22 : 0.14,
                    ),
                    fallbackIcon: Icons.music_note_rounded,
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
                  onTap: () => playerService.playQueue(
                    tracks,
                    startIndex: index,
                    sourceTitle: l10n.folders,
                  ),
                  onLongPress: () => _confirmDeleteTrack(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmDeleteTrack(Track track) async {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.delete,
          style: TextStyle(
            color: isDark ? Colors.white : InzxColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          l10n.deleteDownloadWarning(track.title),
          style: TextStyle(
            color: isDark ? Colors.white70 : InzxColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final playerService = ref.read(audioPlayerServiceProvider);
      final localTracksNotifier = ref.read(localTracksProvider.notifier);
      final downloadManagerNotifier = ref.read(downloadManagerProvider.notifier);
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      // Check storage deletion permission on Android
      if (Platform.isAndroid &&
          !await LocalMusicScanner.hasDeleteStoragePermission()) {
        final granted =
            await LocalMusicScanner.requestDeleteStoragePermission();
        if (!granted) {
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text(l10n.storagePermissionRequiredMessage),
                action: SnackBarAction(
                  label: l10n.openSettings,
                  onPressed: () => LocalMusicScanner.openSettings(),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return false;
        }
      }

      final success = await localTracksNotifier.deleteTrack(
        track,
        deleteFileFromDisk: true,
      );

      if (success) {
        final queueIndex = playerService.queue.indexWhere((t) =>
            t.id == track.id ||
            (track.localFilePath != null &&
                t.localFilePath == track.localFilePath));
        if (queueIndex != -1) {
          playerService.removeFromQueue(queueIndex);
        } else if (playerService.currentTrack?.id == track.id ||
            (track.localFilePath != null &&
                playerService.currentTrack?.localFilePath ==
                    track.localFilePath)) {
          playerService.stop();
        }

        await downloadManagerNotifier.removeDownload(track.id);

        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(l10n.deletedTrack(track.title)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return true;
      } else {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(l10n.storagePermissionRequiredMessage),
              action: SnackBarAction(
                label: l10n.openSettings,
                onPressed: () => LocalMusicScanner.openSettings(),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    }
    return false;
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

    var folderPath = await LocalMusicScanner.pickFolder();
    // Linux's folder dialog comes from zenity, kdialog or qarma; without one
    // there's no dialog at all, so ask for the path instead.
    if (folderPath == null &&
        LocalMusicScanner.lastPickerError != null &&
        Platform.isLinux &&
        mounted) {
      folderPath = await _askForFolderPath();
    }
    if (folderPath == null || !mounted) return;
    final added = ref
        .read(localMusicFoldersProvider.notifier)
        .addFolder(folderPath);
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That folder is already in your library.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    // Scan immediately without showing extra popup dialog
    _scanFolder(folderPath);
  }

  /// A folder typed in, for when there's no folder dialog to pick one with.
  Future<String?> _askForFolderPath() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a music folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The folder picker needs zenity or kdialog installed. You can '
              'type the folder’s path instead.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/home/you/Music',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    var trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home != null) trimmed = '$home${trimmed.substring(1)}';
    }
    if (!Directory(trimmed).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No folder at $trimmed')),
        );
      }
      return null;
    }
    return trimmed;
  }

  void _showPermissionDialog({bool isPermanentlyDenied = false}) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.read(effectiveAccentColorProvider);

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
                l10n.permissionRequired,
                style: TextStyle(
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.storagePermissionRequiredMessage,
          style: TextStyle(
            color: isDark ? Colors.white70 : InzxColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final opened = await LocalMusicScanner.openSettings();
              if (!opened) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.couldNotOpenSettingsPermission)),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.settings_rounded),
            label: Text(l10n.openSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _scanFolder(String path) async {
    final l10n = context.l10n;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.scanningForMusic),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() => _isSyncing = true);

    final tracks = await LocalMusicScanner.scanDirectory(path);

    if (mounted) {
      setState(() => _isSyncing = false);
      await ref
          .read(localTracksProvider.notifier)
          .syncFolderTracks(path, tracks);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.foundSongsCount(tracks.length)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _syncFoldersAutomatically() async {
    final l10n = context.l10n;
    final folders = ref.read(localMusicFoldersProvider);
    if (folders.isEmpty) {
      _pickFolder();
      return;
    }

    setState(() => _isSyncing = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.scanningForMusic),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // A folder that isn't there right now (an unplugged drive) is left
    // alone: scanning it would find nothing and drop its songs.
    final present = [
      for (final folder in folders)
        if (Directory(folder).existsSync()) folder,
    ];
    final allTracks = <Track>[];
    for (final folder in present) {
      final tracks = await LocalMusicScanner.scanDirectory(folder);
      allTracks.addAll(tracks);
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      await ref
          .read(localTracksProvider.notifier)
          .syncAllFolders(present, allTracks);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.foundSongsInFoldersCount(allTracks.length, folders.length),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
