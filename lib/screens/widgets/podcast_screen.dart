import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/deep_link_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'playlist_screen.dart' show playlistColorsProvider;
import 'podcast_video_screen.dart';
import 'mini_player.dart';
import 'now_playing_screen.dart';

/// Dedicated screen for a podcast show: header, save/subscribe, show
/// description, and a list of episodes with rich (timestamp/link) descriptions.
class PodcastScreen extends ConsumerStatefulWidget {
  final String podcastId;
  final String? title;
  final String? thumbnailUrl;

  const PodcastScreen({
    super.key,
    required this.podcastId,
    this.title,
    this.thumbnailUrl,
  });

  static void open(
    BuildContext context, {
    required String podcastId,
    String? title,
    String? thumbnailUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PodcastScreen(
          podcastId: podcastId,
          title: title,
          thumbnailUrl: thumbnailUrl,
        ),
      ),
    );
  }

  @override
  ConsumerState<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends ConsumerState<PodcastScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Episode>? _episodes;
  String? _continuation;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _lastLoadedPodcastId;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore([Podcast? podcast]) async {
    final cont = _continuation;
    if (cont == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final (more, nextCont) =
        await ref.read(innerTubeServiceProvider).getPodcastContinuation(
              continuationToken: cont,
              podcastId: widget.podcastId,
              podcastTitle: podcast?.title ?? widget.title ?? '',
              author: podcast?.author,
            );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (more.isNotEmpty) {
        _episodes = [...?_episodes, ...more];
      }
      _continuation = nextCont;
      _hasMore = nextCont != null && nextCont.isNotEmpty;
    });
  }

  Future<void> _playEpisode(Podcast podcast, int index) async {
    final player = ref.read(audioPlayerServiceProvider);
    final eps = _episodes ?? podcast.episodes;
    final tracks = eps.map((e) => e.toTrack()).toList();
    await player.playQueue(
      tracks,
      startIndex: index,
      sourceId: podcast.id,
      sourceTitle: podcast.title,
    );
    if (mounted) {
      NowPlayingScreen.show(context);
    }
  }

  Future<void> _seekWithinEpisode(Episode ep, Duration position) async {
    final player = ref.read(audioPlayerServiceProvider);
    final current = ref.read(currentTrackProvider);
    if (current?.id == ep.videoId) {
      await player.seek(position);
    } else {
      await player.playQueue([ep.toTrack()], sourceId: ep.podcastId);
      // Best-effort: seek once the stream has had a moment to load.
      if (position > Duration.zero) {
        await Future.delayed(const Duration(milliseconds: 700));
        await player.seek(position);
      }
    }
    if (mounted) {
      NowPlayingScreen.show(context);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _toggleSave(Podcast podcast) async {
    final current = ref.read(savedPodcastsProvider).contains(
          SavedPodcastsNotifier.normalize(podcast.id),
        );
    // setSaved updates the local store immediately (so it persists on return)
    // and fires the server call.
    await ref
        .read(ytMusicPodcastSaveActionProvider)
        .setSaved(podcast.id, !current);
  }

  void _sharePodcast(Podcast? podcast) {
    final id = podcast?.id ?? widget.podcastId;
    final shareUrl = DeepLinkHandler.createShareUrl('podcast', id);
    final title = podcast?.title ?? widget.title ?? 'Podcast';
    SharePlus.instance.share(ShareParams(
      text: 'Listen to $title on Inzx: $shareUrl',
    ));
  }

  void _shareEpisode(Episode ep) {
    final shareUrl = DeepLinkHandler.createShareUrl('song', ep.videoId);
    SharePlus.instance.share(ShareParams(
      text: 'Check out "${ep.title}" on Inzx: $shareUrl',
    ));
  }

  void _openVideo(Episode ep) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PodcastVideoScreen(episode: ep)),
    );
  }

  void _openEpisodeDetails(Episode ep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EpisodeDetailsSheet(
        episode: ep,
        onPlay: () => _seekWithinEpisode(ep, Duration.zero),
        onWatch: () => _openVideo(ep),
        onQueue: () {
          ref.read(audioPlayerServiceProvider).addToQueue([ep.toTrack()]);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Added to queue'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        onSeek: (pos) => _seekWithinEpisode(ep, pos),
        onLink: _openLink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final liveAccent = ref.watch(effectiveAccentColorProvider);
    final async = ref.watch(ytMusicPodcastProvider(widget.podcastId));
    final podcast = async.valueOrNull;

    // Extract dynamic palette color from podcast cover or initial thumbnail
    final bgThumbnailUrl = podcast?.thumbnailUrl ?? widget.thumbnailUrl;
    final dynamicColor = bgThumbnailUrl != null
        ? ref.watch(playlistColorsProvider(bgThumbnailUrl)).valueOrNull
        : null;
    final themeColor = dynamicColor ?? liveAccent;
    final accent = themeColor;

    final textColor = isDark ? Colors.white : colorScheme.onSurface;
    final secondary = textColor.withValues(alpha: 0.6);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      body: Stack(
        children: [
          // Background - Smooth 3-stop fading gradient like PlaylistScreen
          _buildBackground(context, bgThumbnailUrl, themeColor),

          async.when(
            loading: () => _scaffoldBody(
              isDark,
              textColor,
              const Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _scaffoldBody(
              isDark,
              textColor,
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Couldn\'t load podcast.\n$e',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary)),
                ),
              ),
            ),
            data: (podcast) {
              if (podcast == null) {
                return _scaffoldBody(
                  isDark,
                  textColor,
                  Center(
                    child: Text('Podcast not found',
                        style: TextStyle(color: secondary)),
                  ),
                );
              }
              if (_lastLoadedPodcastId != podcast.id) {
                _lastLoadedPodcastId = podcast.id;
                _episodes = List<Episode>.from(podcast.episodes);
                _continuation = podcast.continuation;
                _hasMore = _continuation != null && _continuation!.isNotEmpty;
              }
              final episodes = _episodes ?? podcast.episodes;
              final norm = SavedPodcastsNotifier.normalize(podcast.id);
              // "New Episodes" (RDPN), "Episodes for Later" (SE) and library
              // feeds (FE…) are auto-lists, not saveable shows.
              final isSaveable = !(norm.startsWith('RDPN') ||
                  norm == 'SE' ||
                  norm.startsWith('FE'));
              // Loading this also seeds the local saved store from the server.
              ref.watch(ytMusicSavedPodcastsProvider);
              final saved =
                  ref.watch(savedPodcastsProvider).contains(norm) ||
                      podcast.saved;
              final currentTrack = ref.watch(currentTrackProvider);

              // A Stack so the mini player floats over the list.
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverAppBar(
                          pinned: true,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          iconTheme: IconThemeData(color: textColor),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.share_rounded),
                              tooltip: 'Share',
                              onPressed: () => _sharePodcast(podcast),
                            ),
                          ],
                        ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Cover
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 190,
                          height: 190,
                          child: (podcast.thumbnailUrl ?? widget.thumbnailUrl) !=
                                  null
                              ? CachedNetworkImage(
                                  imageUrl: (podcast.thumbnailUrl ??
                                      widget.thumbnailUrl)!,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: isDark
                                      ? Colors.grey[850]
                                      : Colors.grey[300],
                                  child: Icon(Icons.podcasts_rounded,
                                      size: 64, color: secondary),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        podcast.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (podcast.author != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          podcast.author!,
                          style: TextStyle(color: secondary, fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Actions: Play latest + Save + Share
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: episodes.isEmpty
                                ? null
                                : () => _playEpisode(podcast, 0),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 12),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play latest'),
                          ),
                          if (isSaveable)
                            OutlinedButton.icon(
                              onPressed: () => _toggleSave(podcast),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: saved ? accent : textColor,
                                side: BorderSide(
                                  color: saved
                                      ? accent
                                      : textColor.withValues(alpha: 0.3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                              ),
                              icon: Icon(
                                saved
                                    ? Icons.check_rounded
                                    : Icons.library_add_outlined,
                              ),
                              label: Text(
                                  saved ? 'In library' : 'Save to library'),
                            ),
                        ],
                      ),
                      if (podcast.description != null &&
                          podcast.description!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () => setState(
                                () => _descExpanded = !_descExpanded),
                            child: RichDescription(
                              text: podcast.description!,
                              color: secondary,
                              linkColor: accent,
                              maxLines: _descExpanded ? null : 3,
                              onLink: _openLink,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Episodes',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _EpisodeTile(
                    episode: episodes[index],
                    isPlaying: currentTrack?.id ==
                        episodes[index].videoId,
                    isDark: isDark,
                    textColor: textColor,
                    secondary: secondary,
                    accent: accent,
                    onPlay: () => _playEpisode(podcast, index),
                    onWatch: () => _openVideo(episodes[index]),
                    onDetails: () => _openEpisodeDetails(episodes[index]),
                    onShare: () => _shareEpisode(episodes[index]),
                    onQueue: () {
                      ref
                          .read(audioPlayerServiceProvider)
                          .addToQueue([episodes[index].toTrack()]);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Added to queue'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  childCount: episodes.length,
                ),
              ),
              if (_loadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                )
              else if (_hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () => _loadMore(podcast),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load more episodes'),
                        style: TextButton.styleFrom(foregroundColor: secondary),
                      ),
                    ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
        if (currentTrack != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MusicMiniPlayer(
              onTap: () => NowPlayingScreen.show(context),
            ),
          ),
      ],
    );
        },
      ),
        ],
      ),
    );
  }

  Widget _buildBackground(
    BuildContext context,
    String? imageUrl,
    Color themeColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 100,
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.5 : 0.5,
              ),
              colorBlendMode: isDark ? BlendMode.darken : BlendMode.lighten,
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        themeColor.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                        Colors.black,
                      ]
                    : [
                        themeColor.withValues(alpha: 0.14),
                        colorScheme.surface.withValues(alpha: 0.75),
                        colorScheme.surface,
                      ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaffoldBody(bool isDark, Color textColor, Widget child) {
    final currentTrack = ref.watch(currentTrackProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: child),
                if (currentTrack != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MusicMiniPlayer(
                      onTap: () => NowPlayingScreen.show(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final bool isPlaying;
  final bool isDark;
  final Color textColor;
  final Color secondary;
  final Color accent;
  final VoidCallback onPlay;
  final VoidCallback onWatch;
  final VoidCallback onQueue;
  final VoidCallback onShare;
  final VoidCallback onDetails;

  const _EpisodeTile({
    required this.episode,
    required this.isPlaying,
    required this.isDark,
    required this.textColor,
    required this.secondary,
    required this.accent,
    required this.onPlay,
    required this.onWatch,
    required this.onQueue,
    required this.onShare,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onPlay,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 60,
                    child: episode.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: episode.thumbnailUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: isDark
                                ? Colors.grey[850]
                                : Colors.grey[300]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onDetails,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPlaying ? accent : textColor,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [episode.subtitle, episode.durationText]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (episode.progress > 0.01)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: episode.progress,
                  minHeight: 3,
                  backgroundColor: textColor.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
          // Action row: Play, Video, Queue, Share
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _actionChip(
                    Icons.play_arrow_rounded,
                    'Play',
                    onPlay,
                  ),
                  _actionChip(
                    Icons.smart_display_outlined,
                    'Video',
                    onWatch,
                  ),
                  _actionChip(
                    Icons.add_to_queue_rounded,
                    'Queue',
                    onQueue,
                  ),
                  _actionChip(
                    Icons.share_rounded,
                    'Share',
                    onShare,
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 20,
            color: textColor.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: secondary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Renders a description with tappable timestamps (seek) and URLs (open).
class RichDescription extends StatelessWidget {
  final String text;
  final Color color;
  final Color linkColor;
  final int? maxLines;
  final ValueChanged<String> onLink;
  final ValueChanged<Duration>? onTimestamp;

  const RichDescription({
    super.key,
    required this.text,
    required this.color,
    required this.linkColor,
    required this.maxLines,
    required this.onLink,
    this.onTimestamp,
  });

  static final _pattern = RegExp(
    r'(https?:\/\/[^\s]+)|(\b\d{1,2}:\d{2}(?::\d{2})?\b)',
  );

  Duration _parseTimestamp(String t) {
    final parts = t.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration(minutes: parts[0], seconds: parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: color, fontSize: 13, height: 1.4);
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final matched = m.group(0)!;
      final isUrl = m.group(1) != null;
      if (isUrl) {
        spans.add(TextSpan(
          text: matched,
          style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
          recognizer: (TapGestureRecognizer()..onTap = () => onLink(matched)),
        ));
      } else if (onTimestamp != null) {
        spans.add(TextSpan(
          text: matched,
          style: TextStyle(color: linkColor, fontWeight: FontWeight.w600),
          recognizer: (TapGestureRecognizer()
            ..onTap = () => onTimestamp!(_parseTimestamp(matched))),
        ));
      } else {
        // Timestamp without a seek handler (show description) — plain accent.
        spans.add(TextSpan(text: matched, style: TextStyle(color: linkColor)));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow:
          maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

/// Bottom sheet displaying the episode header, audio/video actions, and full
/// show notes retrieved from YouTube Music's MPED endpoint.
class _EpisodeDetailsSheet extends ConsumerWidget {
  final Episode episode;
  final VoidCallback onPlay;
  final VoidCallback onWatch;
  final VoidCallback onQueue;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<String> onLink;

  const _EpisodeDetailsSheet({
    required this.episode,
    required this.onPlay,
    required this.onWatch,
    required this.onQueue,
    required this.onSeek,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = ref.watch(effectiveAccentColorProvider);
    final textColor = isDark ? Colors.white : colorScheme.onSurface;
    final secondary = textColor.withValues(alpha: 0.6);
    final detailsAsync =
        ref.watch(ytMusicEpisodeDetailsProvider(episode.videoId));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181B) : colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    // Header: Cover + Title
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: episode.thumbnailUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: episode.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: isDark
                                        ? Colors.grey[850]
                                        : Colors.grey[300],
                                    child: Icon(Icons.podcasts_rounded,
                                        size: 36, color: secondary),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                episode.title,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (episode.podcastTitle.isNotEmpty)
                                    episode.podcastTitle,
                                  episode.subtitle,
                                  episode.durationText,
                                ]
                                    .where((e) => e != null && e.isNotEmpty)
                                    .join(' • '),
                                style: TextStyle(
                                    color: secondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Action row
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onPlay();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onWatch();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          icon: const Icon(Icons.smart_display_outlined),
                          label: const Text('Video'),
                        ),
                        IconButton(
                          onPressed: onQueue,
                          icon: const Icon(Icons.add_to_queue_rounded),
                          tooltip: 'Add to queue',
                          color: secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: textColor.withValues(alpha: 0.08)),
                    const SizedBox(height: 12),
                    Text(
                      'Episode Notes',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    detailsAsync.when(
                      loading: () {
                        // While full notes are loading, show preview text if available
                        if (episode.description != null &&
                            episode.description!.isNotEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichDescription(
                                text: episode.description!,
                                color: secondary,
                                linkColor: accent,
                                maxLines: null,
                                onLink: onLink,
                                onTimestamp: (pos) {
                                  Navigator.pop(context);
                                  onSeek(pos);
                                },
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: accent),
                                ),
                              ),
                            ],
                          );
                        }
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: accent),
                          ),
                        );
                      },
                      error: (_, _) {
                        final desc = episode.description ??
                            'No notes available for this episode.';
                        return RichDescription(
                          text: desc,
                          color: secondary,
                          linkColor: accent,
                          maxLines: null,
                          onLink: onLink,
                          onTimestamp: (pos) {
                            Navigator.pop(context);
                            onSeek(pos);
                          },
                        );
                      },
                      data: (data) {
                        final fullDesc = data?['description'] as String? ??
                            episode.description;
                        if (fullDesc == null || fullDesc.isEmpty) {
                          return Text(
                            'No show notes available.',
                            style: TextStyle(color: secondary, fontSize: 13),
                          );
                        }
                        return RichDescription(
                          text: fullDesc,
                          color: secondary,
                          linkColor: accent,
                          maxLines: null,
                          onLink: onLink,
                          onTimestamp: (pos) {
                            Navigator.pop(context);
                            onSeek(pos);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
