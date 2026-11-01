import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:marquee/marquee.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/design_system/design_system.dart';
import '../../services/deep_link_handler.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/download_service.dart';
import '../../services/local_music_scanner.dart';
import 'album_screen.dart' hide albumColorsProvider;
import 'artist_screen.dart';
import 'podcast_screen.dart' show PodcastScreen;
import 'playlist_picker_sheet.dart';
import 'track_artwork_view.dart';
import 'jams_panel.dart';
import 'sleep_timer_sheet.dart';
import '../../services/sleep_timer_service.dart';

/// Track options bottom sheet
/// Displays categorized, uniform options in glass section cards
class TrackOptionsSheet extends ConsumerStatefulWidget {
  final Track track;
  final String? sourcePlaylistId;
  final bool isLocalPlaylist;

  const TrackOptionsSheet({
    super.key,
    required this.track,
    this.sourcePlaylistId,
    this.isLocalPlaylist = false,
  });

  static void show(
    BuildContext context,
    Track track, {
    String? sourcePlaylistId,
    bool isLocalPlaylist = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TrackOptionsSheet(
        track: track,
        sourcePlaylistId: sourcePlaylistId,
        isLocalPlaylist: isLocalPlaylist,
      ),
    );
  }

  @override
  ConsumerState<TrackOptionsSheet> createState() => _TrackOptionsSheetState();
}

class _TrackOptionsSheetState extends ConsumerState<TrackOptionsSheet> {
  bool _isDismissing = false;
  double _dragOffset = 0.0;

  Track get track => widget.track;

  void _safeDismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final sourcePlaylistId = widget.sourcePlaylistId;
    final isLocalPlaylist = widget.isLocalPlaylist;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);
    final effectiveAccent = ref.watch(effectiveAccentColorProvider);
    final isMediaPlaying = ref.watch(currentTrackProvider) != null;
    final accentColor = (isMediaPlaying && !albumColors.isDefault)
        ? (isDark ? albumColors.accentLight : albumColors.accent)
        : effectiveAccent;

    final sheetBg = isDark
        ? const Color(0xFF141414).withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.94);
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = textColor.withValues(alpha: 0.55);

    final isLiked = ref.watch(isTrackLikedProvider(track.id));
    final playerService = ref.watch(audioPlayerServiceProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: AnimatedSlide(
              offset: Offset(0, _dragOffset / 400.0),
              duration: _dragOffset == 0.0
                  ? const Duration(milliseconds: 200)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: sheetBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.22),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Interactive Top Drag Handle & Header Card
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if (_isDismissing) return;
                        if (details.primaryDelta != null) {
                          setState(() {
                            _dragOffset = (_dragOffset + details.primaryDelta!)
                                .clamp(0.0, 300.0);
                          });
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (_isDismissing) return;
                        final velocity = details.primaryVelocity ?? 0;
                        if (_dragOffset > 75 || velocity > 200) {
                          _safeDismiss();
                        } else {
                          setState(() {
                            _dragOffset = 0.0;
                          });
                        }
                      },
                      onVerticalDragCancel: () {
                        if (!_isDismissing && mounted && _dragOffset > 0) {
                          setState(() {
                            _dragOffset = 0.0;
                          });
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(top: 14, bottom: 8),
                            alignment: Alignment.center,
                            child: Container(
                              width: 42,
                              height: 4.5,
                              decoration: BoxDecoration(
                                color: textColor.withValues(alpha: 0.30),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),

                          // Track Info Header Card
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildHeaderCard(
                              accentColor,
                              textColor,
                              secondaryColor,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),

                    // Scrollable Content
                    Flexible(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (_isDismissing) return false;
                          if (notification is OverscrollNotification &&
                              notification.overscroll < 0) {
                            if (notification.velocity > 250 ||
                                notification.overscroll < -30) {
                              _safeDismiss();
                              return true;
                            }
                          } else if (notification is ScrollEndNotification) {
                            if (notification.metrics.pixels < -35) {
                              _safeDismiss();
                              return true;
                            }
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                      const SizedBox(height: 16),

                      // SECTION 1: PLAYBACK & QUEUE
                      _buildSectionTitle('PLAYBACK & QUEUE', secondaryColor),
                      const SizedBox(height: 6),
                      _buildSectionCard(
                        textColor: textColor,
                        children: [
                          // Play Next
                          _buildOptionTile(
                            icon: Iconsax.music_playlist,
                            iconColor: accentColor,
                            title: l10n.playNext,
                            textColor: textColor,
                            onTap: () {
                              playerService.playNext(track);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.playingTrackNext(track.title)),
                                ),
                              );
                            },
                          ),

                          // Add to Queue
                          _buildOptionTile(
                            icon: Iconsax.add_square,
                            iconColor: accentColor,
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

                          // Start Radio
                          _buildOptionTile(
                            icon: Iconsax.radio,
                            iconColor: accentColor,
                            title: l10n.startRadio,
                            textColor: textColor,
                            onTap: () {
                              playerService.startRadio(track);
                              Navigator.pop(context);
                            },
                          ),

                          // Sleep timer (only from the song that's playing)
                          if (ref.watch(currentTrackProvider)?.id == track.id)
                            ListenableBuilder(
                              listenable: SleepTimerService.instance,
                              builder: (context, _) {
                                final left =
                                    SleepTimerService.instance.remaining;
                                return _buildOptionTile(
                                  icon: Iconsax.timer_1,
                                  iconColor: accentColor,
                                  title: left == null
                                      ? 'Sleep timer'
                                      : 'Sleep timer · ${SleepTimerService.format(left, precise: true)} left',
                                  textColor: textColor,
                                  onTap: () {
                                    final navigator = Navigator.of(context);
                                    final sheetContext = navigator.context;
                                    navigator.pop();
                                    SleepTimerSheet.show(
                                      sheetContext,
                                      accentColor: accentColor,
                                    );
                                  },
                                );
                              },
                            ),

                          // Play Next in Jam (Conditional)
                          Consumer(
                            builder: (context, ref, child) {
                              final isInJam = ref.watch(isInJamSessionProvider);
                              final canControlPlayback = ref.watch(
                                canControlJamPlaybackProvider,
                              );
                              if (!isInJam || !canControlPlayback) {
                                return const SizedBox.shrink();
                              }
                              return _buildOptionTile(
                                icon: Iconsax.music_playlist,
                                iconColor: Colors.purpleAccent,
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

                          // Add to Jam Queue (Conditional)
                          Consumer(
                            builder: (context, ref, child) {
                              final isInJam = ref.watch(isInJamSessionProvider);
                              final canControlPlayback = ref.watch(
                                canControlJamPlaybackProvider,
                              );
                              if (!isInJam || !canControlPlayback) {
                                return const SizedBox.shrink();
                              }
                              return _buildOptionTile(
                                icon: Iconsax.profile_2user,
                                iconColor: Colors.purpleAccent,
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
                        ],
                      ),

                      const SizedBox(height: 14),

                      // SECTION 2: LIBRARY & PLAYLISTS
                      _buildSectionTitle('LIBRARY & PLAYLISTS', secondaryColor),
                      const SizedBox(height: 6),
                      _buildSectionCard(
                        textColor: textColor,
                        children: [
                          // Like / Unlike
                          _buildOptionTile(
                            icon: isLiked ? Iconsax.heart5 : Iconsax.heart,
                            iconColor: isLiked ? Colors.redAccent : accentColor,
                            title: isLiked
                                ? l10n.removeFromLikedSongs
                                : l10n.addToLikedSongs,
                            textColor: textColor,
                            onTap: () {
                              _toggleLike(ref, isLiked);
                              Navigator.pop(context);
                            },
                          ),

                          // Add to Playlist
                          _buildOptionTile(
                            icon: Iconsax.music_square_add,
                            iconColor: accentColor,
                            title: l10n.addToPlaylist,
                            textColor: textColor,
                            onTap: () {
                              Navigator.pop(context);
                              PlaylistPickerSheet.show(context, track);
                            },
                          ),

                          // Download / Remove Download / Delete Local File
                          Consumer(
                            builder: (context, ref, child) {
                              final isDownloaded = ref.watch(
                                isTrackDownloadedProvider(track.id),
                              );
                              final isLocalFile = track.localFilePath != null &&
                                  track.localFilePath!.trim().isNotEmpty;
                              final progress = ref.watch(
                                trackDownloadProgressProvider(track.id),
                              );

                              if (isDownloaded || isLocalFile) {
                                return _buildOptionTile(
                                  icon: Iconsax.trash,
                                  iconColor: Colors.redAccent,
                                  title: isDownloaded
                                      ? l10n.deleteDownload
                                      : l10n.delete,
                                  textColor: textColor,
                                  onTap: () {
                                    _showDeleteTrackConfirmation(
                                      context,
                                      track,
                                    );
                                  },
                                );
                              }

                              return _buildOptionTile(
                                icon: Iconsax.document_download,
                                iconColor: accentColor,
                                title: progress != null
                                    ? l10n.downloadingProgress(
                                        (progress * 100).toInt(),
                                      )
                                    : l10n.download,
                                textColor: textColor,
                                onTap: progress != null
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

                          // Remove from Playlist (if applicable)
                          if (sourcePlaylistId != null &&
                              (isLocalPlaylist || track.setVideoId != null))
                            _buildOptionTile(
                              icon: Iconsax.trash,
                              iconColor: Colors.redAccent,
                              title: l10n.removeFromPlaylist,
                              textColor: textColor,
                              onTap: () async {
                                if (isLocalPlaylist) {
                                  ref
                                      .read(localPlaylistsProvider.notifier)
                                      .removeTrackFromPlaylist(sourcePlaylistId, track.id);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.removedFromPlaylist)),
                                  );
                                } else if (track.setVideoId != null) {
                                  final container = ProviderScope.containerOf(context, listen: false);
                                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                                  final localL10n = l10n;
                                  final ytAction = container.read(ytMusicPlaylistActionProvider);
                                  final notifier = container.read(ytMusicPlaylistProvider(sourcePlaylistId).notifier);

                                  Navigator.pop(context);
                                  final success = await ytAction.removeSong(sourcePlaylistId, track.id, track.setVideoId!);

                                  if (success) {
                                    await notifier.removeTrackOptimistically(track.id);
                                    container.invalidate(ytMusicPlaylistProvider(sourcePlaylistId));
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(content: Text(localL10n.removedFromPlaylist)),
                                    );
                                  } else {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(content: Text(localL10n.unknownError)),
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // SECTION 3: EXPLORE & SHARE
                      _buildSectionTitle('EXPLORE & SHARE', secondaryColor),
                      const SizedBox(height: 6),
                      _buildSectionCard(
                        textColor: textColor,
                        children: [
                          // Go to Podcast (if episode)
                          if (track.isPodcast || (track.podcastId != null && track.podcastId!.isNotEmpty))
                            _buildOptionTile(
                              icon: Icons.podcasts_rounded,
                              iconColor: accentColor,
                              title: 'Go to Podcast',
                              textColor: textColor,
                              onTap: () {
                                Navigator.pop(context);
                                PodcastScreen.open(
                                  context,
                                  podcastId: track.podcastId!,
                                  title: track.album ?? track.artist,
                                  thumbnailUrl: track.thumbnailUrl,
                                );
                              },
                            ),

                          // Go to Artist
                          if (track.artistId.isNotEmpty && !track.isPodcast && (track.podcastId == null || track.podcastId!.isEmpty))
                            _buildOptionTile(
                              icon: Iconsax.profile_2user,
                              iconColor: accentColor,
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

                          // Go to Album
                          if (track.albumId != null)
                            _buildOptionTile(
                              icon: Iconsax.music_dashboard,
                              iconColor: accentColor,
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

                          // Share
                          _buildOptionTile(
                            icon: Icons.share_rounded,
                            iconColor: accentColor,
                            title: l10n.share,
                            textColor: textColor,
                            onTap: () {
                              Navigator.pop(context);
                              final url = DeepLinkHandler.createShareUrl('song', track.id);
                              SharePlus.instance.share(
                                ShareParams(
                                  text: l10n.shareTrackText(track.title, track.artist, url),
                                ),
                              );
                            },
                          ),

                          // Listen Together (Jam)
                          Builder(
                            builder: (context) {
                              final isInSession = ref.watch(isInJamSessionProvider);
                              return _buildOptionTile(
                                icon: Iconsax.profile_2user,
                                iconColor: accentColor,
                                title: isInSession ? 'Jam Session' : 'Listen Together',
                                textColor: textColor,
                                onTap: () {
                                  Navigator.pop(context);
                                  final isDark = Theme.of(context).brightness == Brightness.dark;
                                  final albumColors = ref.read(albumColorsProvider);
                                  final bgColor = isDark
                                      ? albumColors.backgroundPrimary
                                      : InzxColors.background;
                                  final txtColor = isDark
                                      ? albumColors.onBackground
                                      : InzxColors.textPrimary;
                                  JamsPanel.show(
                                    context,
                                    backgroundColor: bgColor,
                                    textColor: txtColor,
                                    accentColor: albumColors.accent,
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
),
),
),
);
  }

  Widget _buildHeaderCard(Color accentColor, Color textColor, Color secondaryColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          // Album Artwork with glow
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 52,
                height: 52,
                child: TrackArtworkView(
                  track: track,
                  width: 52,
                  height: 52,
                  borderRadius: BorderRadius.circular(12),
                  fallback: Container(
                    color: accentColor.withValues(alpha: 0.2),
                    child: Icon(
                      Iconsax.music,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title with Marquee on overflow
                LayoutBuilder(
                  builder: (context, constraints) {
                    final titleStyle = TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    );
                    final textPainter = TextPainter(
                      text: TextSpan(text: track.title, style: titleStyle),
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    )..layout();

                    if (textPainter.width > constraints.maxWidth) {
                      return SizedBox(
                        height: 22,
                        child: Marquee(
                          text: track.title,
                          style: titleStyle,
                          scrollAxis: Axis.horizontal,
                          blankSpace: 36.0,
                          velocity: 28.0,
                          pauseAfterRound: const Duration(seconds: 2),
                          startPadding: 0.0,
                          accelerationDuration: const Duration(seconds: 1),
                          accelerationCurve: Curves.linear,
                          decelerationDuration:
                              const Duration(milliseconds: 500),
                        ),
                      );
                    }
                    return Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    );
                  },
                ),
                const SizedBox(height: 2),
                // Artist with Marquee on overflow
                LayoutBuilder(
                  builder: (context, constraints) {
                    final artistStyle = TextStyle(
                      fontSize: 13,
                      color: secondaryColor,
                    );
                    final textPainter = TextPainter(
                      text: TextSpan(text: track.artist, style: artistStyle),
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    )..layout();

                    if (textPainter.width > constraints.maxWidth) {
                      return SizedBox(
                        height: 18,
                        child: Marquee(
                          text: track.artist,
                          style: artistStyle,
                          scrollAxis: Axis.horizontal,
                          blankSpace: 36.0,
                          velocity: 28.0,
                          pauseAfterRound: const Duration(seconds: 2),
                          startPadding: 0.0,
                          accelerationDuration: const Duration(seconds: 1),
                          accelerationCurve: Curves.linear,
                          decelerationDuration:
                              const Duration(milliseconds: 500),
                        ),
                      );
                    }
                    return Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: artistStyle,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color secondaryColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: secondaryColor,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required Color textColor,
    required List<Widget> children,
  }) {
    // Filter out SizedBox.shrink() items
    final validChildren = children.where((w) => w is! SizedBox).toList();

    return Container(
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: validChildren,
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return BouncyTouch(
      style: BouncyStyle.card,
      customScale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: textColor.withValues(alpha: 0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLike(WidgetRef ref, bool isLiked) async {
    await toggleTrackLike(ref: ref, track: track);
  }

  void _showDeleteTrackConfirmation(
    BuildContext context,
    Track track,
  ) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (dialogContext, dialogRef, child) {
          final isDownloaded = dialogRef.watch(
            isTrackDownloadedProvider(track.id),
          );

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              isDownloaded ? l10n.deleteDownloadQuestion : l10n.delete,
              style: TextStyle(
                color: isDark ? Colors.white : InzxColors.textPrimary,
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
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  l10n.cancel,
                  style:
                      TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final playerService =
                      dialogRef.read(audioPlayerServiceProvider);
                  final localTracksNotifier =
                      dialogRef.read(localTracksProvider.notifier);
                  final downloadManagerNotifier =
                      dialogRef.read(downloadManagerProvider.notifier);

                  Navigator.pop(dialogContext);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }

                  // Check storage deletion permission on Android if deleting a local file
                  if (Platform.isAndroid &&
                      track.localFilePath != null &&
                      track.localFilePath!.isNotEmpty &&
                      !await LocalMusicScanner.hasDeleteStoragePermission()) {
                    final granted =
                        await LocalMusicScanner.requestDeleteStoragePermission();
                    if (!granted) {
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
                      return;
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

                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.deletedTrack(track.title)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
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
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(isDownloaded ? l10n.deleteDownload : l10n.delete),
              ),
            ],
          );
        },
      ),
    );
  }
}
