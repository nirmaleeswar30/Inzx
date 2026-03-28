import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/download_service.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_picker_sheet.dart';

/// Track options bottom sheet
/// Shows options like: Like, Add to queue, Play next, Add to playlist, Go to artist/album
class TrackOptionsSheet extends ConsumerWidget {
  final Track track;

  const TrackOptionsSheet({super.key, required this.track});

  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TrackOptionsSheet(track: track),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = textColor.withValues(alpha: 0.6);

    final isLiked = ref.watch(isTrackLikedProvider(track.id));
    final playerService = ref.watch(audioPlayerServiceProvider);

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Track info header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: track.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: track.thumbnailUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: colorScheme.primaryContainer,
                                child: Icon(
                                  Iconsax.music,
                                  color: colorScheme.primary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: textColor,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Options list
              _buildOption(
                context,
                icon: isLiked ? Iconsax.heart5 : Iconsax.heart,
                iconColor: isLiked ? Colors.red : textColor,
                title: isLiked
                    ? l10n.removeFromLikedSongs
                    : l10n.addToLikedSongs,
                textColor: textColor,
                onTap: () async {
                  // Use explicit like/unlike based on current state
                  if (isLiked) {
                    // Unlike: remove from local state and mark as explicitly unliked
                    ref.read(likedSongsProvider.notifier).unlike(track.id);
                    ref
                        .read(explicitlyUnlikedIdsProvider.notifier)
                        .update((state) => {...state, track.id});
                  } else {
                    // Like: add to local state and remove from explicitly unliked
                    ref.read(likedSongsProvider.notifier).like(track);
                    ref
                        .read(explicitlyUnlikedIdsProvider.notifier)
                        .update(
                          (state) =>
                              state.where((id) => id != track.id).toSet(),
                        );
                  }

                  // Also sync to YT Music if logged in
                  final authState = ref.read(ytMusicAuthStateProvider);
                  if (authState.isLoggedIn) {
                    final likeAction = ref.read(ytMusicLikeActionProvider);
                    if (isLiked) {
                      await likeAction.unlike(track.id);
                    } else {
                      await likeAction.like(track.id);
                    }
                    // Refresh liked songs from YT Music
                    ref.invalidate(ytMusicLikedSongsProvider);
                  }

                  if (context.mounted) Navigator.pop(context);
                },
              ),

              _buildOption(
                context,
                icon: Iconsax.music_playlist,
                title: l10n.playNext,
                textColor: textColor,
                onTap: () {
                  playerService.playNext(track);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.playingTrackNext(track.title))),
                  );
                },
              ),

              _buildOption(
                context,
                icon: Iconsax.add_square,
                title: l10n.addToQueue,
                textColor: textColor,
                onTap: () {
                  playerService.addToQueue([track]);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.addedTrackToQueue(track.title)),
                    ),
                  );
                },
              ),

              // Play Next in Jam Queue option (only shows when in a jam session with permission)
              Builder(
                builder: (context) {
                  final isInJam = ref.watch(isInJamSessionProvider);
                  final canControlPlayback = ref.watch(
                    canControlJamPlaybackProvider,
                  );
                  if (!isInJam || !canControlPlayback) {
                    return const SizedBox.shrink();
                  }

                  return _buildOption(
                    context,
                    icon: Iconsax.music_playlist,
                    iconColor: Colors.purple,
                    title: l10n.playNextInJam,
                    textColor: textColor,
                    onTap: () async {
                      final jamsService = ref.read(jamsServiceProvider);
                      if (jamsService != null) {
                        await jamsService.playNextInQueue(
                          videoId: track.id,
                          title: track.title,
                          artist: track.artist,
                          thumbnailUrl: track.thumbnailUrl,
                          durationMs: track.duration.inMilliseconds,
                        );
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.playTrackNextInJam(track.title)),
                          ),
                        );
                      }
                    },
                  );
                },
              ),

              // Add to Jam Queue option (only shows when in a jam session with permission)
              Builder(
                builder: (context) {
                  final isInJam = ref.watch(isInJamSessionProvider);
                  final canControlPlayback = ref.watch(
                    canControlJamPlaybackProvider,
                  );
                  if (!isInJam || !canControlPlayback) {
                    return const SizedBox.shrink();
                  }

                  return _buildOption(
                    context,
                    icon: Iconsax.profile_2user,
                    iconColor: Colors.purple,
                    title: l10n.addToJamQueue,
                    textColor: textColor,
                    onTap: () async {
                      final jamsService = ref.read(jamsServiceProvider);
                      if (jamsService != null) {
                        await jamsService.addToQueue(
                          videoId: track.id,
                          title: track.title,
                          artist: track.artist,
                          thumbnailUrl: track.thumbnailUrl,
                          durationMs: track.duration.inMilliseconds,
                        );
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.addedTrackToJamQueue(track.title),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),

              _buildOption(
                context,
                icon: Iconsax.music_square_add,
                title: l10n.addToPlaylist,
                textColor: textColor,
                onTap: () {
                  Navigator.pop(context);
                  PlaylistPickerSheet.show(context, track);
                },
              ),

              // Download option
              Builder(
                builder: (context) {
                  final isDownloaded = ref.watch(
                    isTrackDownloadedProvider(track.id),
                  );
                  final progress = ref.watch(
                    trackDownloadProgressProvider(track.id),
                  );

                  return _buildOption(
                    context,
                    icon: isDownloaded
                        ? Iconsax.tick_circle
                        : Iconsax.document_download,
                    iconColor: isDownloaded ? Colors.green : null,
                    title: isDownloaded
                        ? l10n.downloaded
                        : progress != null
                        ? l10n.downloadingProgress((progress * 100).toInt())
                        : l10n.download,
                    textColor: textColor,
                    onTap: isDownloaded || progress != null
                        ? () => Navigator.pop(context)
                        : () {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .addToQueue(track);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.downloadStartingTrack(track.title),
                                ),
                              ),
                            );
                          },
                  );
                },
              ),

              if (track.albumId != null)
                _buildOption(
                  context,
                  icon: Iconsax.music_dashboard,
                  title: l10n.goToAlbum,
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(context);
                    AlbumScreen.open(
                      context,
                      albumId: track.albumId!,
                      title: track.album,
                      thumbnailUrl: track.thumbnailUrl,
                    );
                  },
                ),

              if (track.artistId.isNotEmpty)
                _buildOption(
                  context,
                  icon: Iconsax.profile_2user,
                  title: l10n.goToArtist,
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(context);
                    ArtistScreen.open(
                      context,
                      artistId: track.artistId,
                      name: track.artist,
                    );
                  },
                ),

              _buildOption(
                context,
                icon: Iconsax.radio,
                title: l10n.startRadio,
                textColor: textColor,
                onTap: () {
                  playerService.playTrack(track, enableRadio: true);
                  Navigator.pop(context);
                },
              ),

              _buildOption(
                context,
                icon: Iconsax.share,
                title: l10n.share,
                textColor: textColor,
                onTap: () {
                  Navigator.pop(context);
                  final url = 'https://music.youtube.com/watch?v=${track.id}';
                  SharePlus.instance.share(
                    ShareParams(
                      text: l10n.shareTrackText(track.title, track.artist, url),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color textColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? textColor),
      title: Text(title, style: TextStyle(color: textColor)),
      onTap: onTap,
    );
  }
}
