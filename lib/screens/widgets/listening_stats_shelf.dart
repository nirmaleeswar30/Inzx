import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/design_system/design_system.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../providers/providers.dart';
import '../../services/listening_stats_service.dart';
import '../statistics_screen.dart';
import 'listening_stats_view.dart';

/// "Your week in music" on Home: this week's listening time, a bar for each
/// day, your top artist and top songs. Opens the statistics page. Hidden
/// until there's a week's listening to show.
class ListeningStatsShelf extends ConsumerWidget {
  const ListeningStatsShelf({super.key, this.padding});

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    final week = stats.summarize(StatsPeriod.week, limit: 4);
    if (week.totalMs < 60000) return const SizedBox.shrink();

    final accent = ref.watch(effectiveAccentColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : InzxColors.textSecondary;
    final topArtist = week.topArtists.isEmpty ? null : week.topArtists.first;
    final maxMs = week.buckets.fold<int>(0, (m, b) => math.max(m, b.ms));

    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => StatisticsScreen.open(context),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(Iconsax.calendar_tick, size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your week in music',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: text,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: secondary),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatListening(week.totalMs),
                            style: TextStyle(
                              fontSize: 34,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                              color: text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${week.plays} plays · ${week.uniqueArtists} artists',
                            style: TextStyle(fontSize: 12.5, color: secondary),
                          ),
                        ],
                      ),
                    ),
                    // A bar for each of the last seven days.
                    SizedBox(
                      height: 52,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final b in week.buckets)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              child: Container(
                                width: 9,
                                height: maxMs == 0
                                    ? 4
                                    : math.max(4, 52 * b.ms / maxMs),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: b.ms == 0
                                      ? secondary.withValues(alpha: 0.2)
                                      : accent.withValues(
                                          alpha: b.isCurrent ? 1 : 0.5,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (topArtist != null || week.topTracks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (topArtist != null) ...[
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 36,
                            child: topArtist.imageUrl == null
                                ? ColoredBox(color: accent)
                                : CachedNetworkImage(
                                    imageUrl: topArtist.imageUrl!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 108,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Top artist',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: secondary,
                                ),
                              ),
                              Text(
                                topArtist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        const Spacer(),
                      // The week's top songs as a little stack of covers.
                      SizedBox(
                        height: 40,
                        width: 40.0 + 24 * (week.topTracks.length - 1),
                        child: Stack(
                          children: [
                            for (final (i, stat)
                                in week.topTracks.reversed.indexed)
                              Positioned(
                                right: 24.0 * i,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF1B1B1F)
                                          : Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: SizedBox.square(
                                      dimension: 36,
                                      child: stat.track.thumbnailUrl == null
                                          ? ColoredBox(
                                              color: accent.withValues(
                                                alpha: 0.4,
                                              ),
                                            )
                                          : CachedNetworkImage(
                                              imageUrl:
                                                  stat.track.thumbnailUrl!,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 108,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
