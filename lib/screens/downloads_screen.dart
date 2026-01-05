import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/design_system/design_system.dart';
import '../services/download_service.dart';
import '../providers/providers.dart';
import 'widgets/track_options_sheet.dart';

/// Downloads screen showing download queue and completed downloads
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadManagerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (downloadState.completedTasks.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: isDark ? Colors.white : Colors.black,
              ),
              onSelected: (value) {
                if (value == 'clear_completed') {
                  ref.read(downloadManagerProvider.notifier).clearCompleted();
                } else if (value == 'clear_failed') {
                  ref.read(downloadManagerProvider.notifier).clearFailed();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear_completed',
                  child: Text('Clear completed'),
                ),
                if (downloadState.failedTasks.isNotEmpty)
                  const PopupMenuItem(
                    value: 'clear_failed',
                    child: Text('Clear failed'),
                  ),
              ],
            ),
        ],
      ),
      body: downloadState.tasks.isEmpty
          ? _buildEmptyState(isDark, colorScheme)
          : _buildDownloadList(
              context,
              ref,
              downloadState,
              isDark,
              colorScheme,
            ),
    );
  }

  Widget _buildEmptyState(bool isDark, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white10
                  : colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.document_download,
              size: 48,
              color: isDark
                  ? Colors.white38
                  : colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No downloads yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Download songs to listen offline',
            style: TextStyle(
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadList(
    BuildContext context,
    WidgetRef ref,
    DownloadManagerState state,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final sections = <Widget>[];

    // Storage info
    if (state.completedTasks.isNotEmpty) {
      sections.add(_buildStorageInfo(state, isDark, colorScheme));
    }

    // Active/Queued downloads
    final activeAndQueued = [...state.activeTasks, ...state.queuedTasks];
    if (activeAndQueued.isNotEmpty) {
      sections.add(
        _buildSection(
          context,
          ref,
          title: 'Downloading',
          tasks: activeAndQueued,
          isDark: isDark,
          colorScheme: colorScheme,
        ),
      );
    }

    // Completed downloads
    if (state.completedTasks.isNotEmpty) {
      sections.add(
        _buildSection(
          context,
          ref,
          title: 'Downloaded (${state.completedTasks.length})',
          tasks: state.completedTasks,
          isDark: isDark,
          colorScheme: colorScheme,
        ),
      );
    }

    // Failed downloads
    if (state.failedTasks.isNotEmpty) {
      sections.add(
        _buildSection(
          context,
          ref,
          title: 'Failed',
          tasks: state.failedTasks,
          isDark: isDark,
          colorScheme: colorScheme,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: sections,
    );
  }

  Widget _buildStorageInfo(
    DownloadManagerState state,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Iconsax.folder_open, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.totalCompleted} songs downloaded',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : MineColors.textPrimary,
                  ),
                ),
                Text(
                  'Using ${state.totalStorageText}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : MineColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required List<DownloadTask> tasks,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ),
        ...tasks.map(
          (task) => _buildDownloadTile(context, ref, task, isDark, colorScheme),
        ),
      ],
    );
  }

  Widget _buildDownloadTile(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final track = task.track;
    final playerService = ref.watch(audioPlayerServiceProvider);

    return ListTile(
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: track.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.thumbnailUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: colorScheme.primaryContainer,
                      child: Icon(Iconsax.music, color: colorScheme.primary),
                    ),
            ),
          ),
          // Download indicator overlay
          if (task.status == DownloadStatus.downloading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: task.progress,
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (task.status == DownloadStatus.completed)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isDark ? Colors.white : MineColors.textPrimary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
          if (task.status == DownloadStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task.progressText,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          if (task.status == DownloadStatus.failed)
            Text(
              'Failed: ${task.error ?? "Unknown error"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
        ],
      ),
      trailing: _buildTrailingAction(context, ref, task, isDark),
      onTap: task.status == DownloadStatus.completed
          ? () => playerService.playTrack(track)
          : null,
      onLongPress: () => TrackOptionsSheet.show(context, track),
    );
  }

  Widget _buildTrailingAction(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
    bool isDark,
  ) {
    switch (task.status) {
      case DownloadStatus.queued:
        return IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          onPressed: () => ref
              .read(downloadManagerProvider.notifier)
              .cancelDownload(task.trackId),
        );
      case DownloadStatus.downloading:
        return IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          onPressed: () => ref
              .read(downloadManagerProvider.notifier)
              .cancelDownload(task.trackId),
        );
      case DownloadStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.sizeText,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : MineColors.textSecondary,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.more_vert,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              onPressed: () => _showCompletedOptions(context, ref, task),
            ),
          ],
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, color: Colors.orange),
          onPressed: () => ref
              .read(downloadManagerProvider.notifier)
              .retryDownload(task.trackId),
        );
      case DownloadStatus.cancelled:
        return IconButton(
          icon: const Icon(Icons.refresh, color: Colors.grey),
          onPressed: () => ref
              .read(downloadManagerProvider.notifier)
              .retryDownload(task.trackId),
        );
    }
  }

  void _showCompletedOptions(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Iconsax.trash),
              title: const Text('Remove download'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(downloadManagerProvider.notifier)
                    .removeDownload(task.trackId);
              },
            ),
          ],
        ),
      ),
    );
  }
}
