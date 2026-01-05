import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../providers/providers.dart';

/// Statistics screen showing listening stats
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: const Text('Statistics'),
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
                    const SnackBar(content: Text('Statistics cleared')),
                  );
                },
                child: const Row(
                  children: [
                    Icon(Iconsax.trash, size: 20),
                    SizedBox(width: 12),
                    Text('Clear Statistics'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: stats.isEmpty
          ? _buildEmpty(isDark)
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

  Widget _buildEmpty(bool isDark) {
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
            'No statistics yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start listening to see your stats',
            style: TextStyle(
              color: isDark ? Colors.white54 : MineColors.textSecondary,
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
    final hours = totalTime.inHours;
    final minutes = totalTime.inMinutes % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : MineColors.textPrimary,
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
                label: 'Total Plays',
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
                value: hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                label: 'Listen Time',
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
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
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
    if (mostPlayed.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Most Played',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : MineColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...mostPlayed.take(10).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final stat = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
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
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
              subtitle: Text(
                stat.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${stat.playCount} plays',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    _formatDuration(stat.totalPlayTime),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m';
  }
}
