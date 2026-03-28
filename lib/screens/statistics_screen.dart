import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../providers/providers.dart';

/// Statistics screen showing listening stats
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final stats = ref.watch(playStatisticsProvider);
    final mostPlayed = ref.watch(mostPlayedTracksProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);

    final totalPlays = stats.values.fold(0, (sum, s) => sum + s.playCount);
    final totalTime = stats.values.fold(
      Duration.zero,
      (sum, s) => sum + s.totalPlayTime,
    );

    return Scaffold(
      backgroundColor: isDark
          ? InzxColors.darkBackground
          : InzxColors.background,
      appBar: AppBar(
        title: Text(l10n.statisticsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton(
            icon: Icon(
              Icons.more_vert,
              color: isDark ? Colors.white : Colors.black,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () {
                  ref.read(playStatisticsProvider.notifier).clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.statisticsCleared)),
                  );
                },
                child: Row(
                  children: [
                    const Icon(Iconsax.trash, size: 20),
                    SizedBox(width: 12),
                    Text(l10n.clearStatistics),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: stats.isEmpty
          ? _buildEmpty(context, isDark)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Overview cards
                _buildOverviewSection(
                  context,
                  isDark,
                  colorScheme,
                  totalPlays,
                  totalTime,
                ),

                const SizedBox(height: 24),

                // Most played tracks
                _buildMostPlayedSection(
                  context,
                  isDark,
                  mostPlayed,
                  playerService,
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Iconsax.chart,
            size: 64,
            color: isDark ? Colors.white38 : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noStatisticsYet,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.startListeningStats,
            style: TextStyle(
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(
    BuildContext context,
    bool isDark,
    ColorScheme colorScheme,
    int totalPlays,
    Duration totalTime,
  ) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.overview,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : InzxColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                isDark: isDark,
                colorScheme: colorScheme,
                icon: Iconsax.play_circle,
                value: totalPlays.toString(),
                label: l10n.totalPlays,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                isDark: isDark,
                colorScheme: colorScheme,
                icon: Iconsax.timer_1,
                value: _formatDuration(context, totalTime),
                label: l10n.listenTime,
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required bool isDark,
    required ColorScheme colorScheme,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildMostPlayedSection(
    BuildContext context,
    bool isDark,
    List<TrackPlayStats> mostPlayed,
    dynamic playerService,
  ) {
    final l10n = context.l10n;
    if (mostPlayed.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mostPlayed,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : InzxColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...mostPlayed.take(10).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final stat = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: index < 3
                            ? Theme.of(context).colorScheme.primary
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: stat.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: stat.thumbnailUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade200,
                              child: const Icon(Iconsax.music, size: 20),
                            ),
                    ),
                  ),
                ],
              ),
              title: Text(
                stat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
              subtitle: Text(
                stat.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.playsCount(stat.playCount),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    _formatDuration(context, stat.totalPlayTime),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _formatDuration(BuildContext context, Duration d) {
    final l10n = context.l10n;
    if (d.inHours > 0) {
      return l10n.durationHoursMinutes(d.inHours, d.inMinutes % 60);
    }
    return l10n.durationMinutesOnly(d.inMinutes);
  }
}
