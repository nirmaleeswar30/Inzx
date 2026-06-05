import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'track_options_sheet.dart';

/// View to display playback history grouped by sections (Today, Yesterday, etc.)
class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    
    // We will rely primarily on the YT Music history sections provider.
    final historyAsync = ref.watch(ytMusicHistorySectionsProvider);
    final playerService = ref.read(audioPlayerServiceProvider);

    return historyAsync.when(
      loading: () => _buildLoadingState(isDark, colorScheme),
      error: (e, stack) => _buildErrorState(context.l10n.errorWithMessage(e.toString()), isDark),
      data: (sections) {
        if (sections.isEmpty) {
          // Fallback to local history if empty
          final localHistory = ref.watch(recentlyPlayedProvider);
          if (localHistory.isEmpty) {
            return _buildEmptyState(isDark, colorScheme);
          }
          
          // Create a pseudo-section for local history
          sections = [
            HistorySection(
              title: context.l10n.recentlyPlayed,
              tracks: localHistory,
            )
          ];
        }
        
        return _buildContent(context, ref, sections, isDark, colorScheme, playerService);
      },
    );
  }

  Widget _buildLoadingState(bool isDark, ColorScheme colorScheme) {
    return const CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.warning_2, size: 48, color: isDark ? Colors.white54 : Colors.black54),
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, ColorScheme colorScheme) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.clock, size: 64, color: isDark ? Colors.white38 : colorScheme.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(
                  context.l10n.noPlaylistsYet, // A generic "nothing here" text
                  style: TextStyle(color: isDark ? Colors.white : colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<HistorySection> sections,
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService,
  ) {
    // Flatten tracks for playback capabilities
    final allTracks = sections.expand((s) => s.tracks).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              context.l10n.historyDescription,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        ...sections.expand((section) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
              child: Text(
                section.title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = section.tracks[index];
                // Find the actual index of this track in the flattened allTracks list
                // for correct playback queueing.
                final globalIndex = _findGlobalIndex(sections, section, index);

                return _buildTrackTile(
                  context,
                  ref,
                  track,
                  allTracks,
                  globalIndex,
                  isDark,
                  colorScheme,
                  playerService,
                );
              },
              childCount: section.tracks.length,
            ),
          ),
        ]),
        
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  int _findGlobalIndex(List<HistorySection> sections, HistorySection currentSection, int trackIndexInSection) {
    int count = 0;
    for (final section in sections) {
      if (section == currentSection) {
        return count + trackIndexInSection;
      }
      count += section.tracks.length;
    }
    return count;
  }

  Widget _buildTrackTile(
    BuildContext context,
    WidgetRef ref,
    Track track,
    List<Track> allTracks,
    int index,
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService,
  ) {
    final isCurrentTrack = ref.watch(currentTrackProvider)?.id == track.id;
    final isPlaying = ref.watch(playbackStateProvider).maybeWhen(
      data: (s) => s.isPlaying,
      orElse: () => false,
    );

    return InkWell(
      onTap: () {
        playerService.playQueue(allTracks, startIndex: index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Thumbnail
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: track.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: track.thumbnailUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                            child: const Center(child: Icon(Icons.music_note)),
                          ),
                  ),
                  if (isCurrentTrack)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: isPlaying
                            ? const Icon(Icons.bar_chart, color: Colors.white, size: 24)
                            : const Icon(Icons.pause, color: Colors.white, size: 24),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isCurrentTrack
                          ? colorScheme.primary
                          : (isDark ? Colors.white : colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (track.isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            'E',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Options
            IconButton(
              icon: Icon(Icons.more_vert, color: isDark ? Colors.white54 : colorScheme.onSurface.withValues(alpha: 0.6)),
              onPressed: () {
                TrackOptionsSheet.show(context, track);
              },
            ),
          ],
        ),
      ),
    );
  }
}
