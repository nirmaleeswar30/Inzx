import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import 'podcast_screen.dart' show RichDescription, PodcastScreen;
import 'youtube_webview_player.dart';
import 'share_sheet.dart';

/// Plays a podcast episode using YouTube's embedded player in a dedicated screen.
///
/// Embedded playback avoids mobile bot-detection / LOGIN_REQUIRED stream blocks,
/// provides full HD resolution, native controls, and allows chapter seeking.
class PodcastVideoScreen extends ConsumerStatefulWidget {
  final Episode episode;

  const PodcastVideoScreen({super.key, required this.episode});

  @override
  ConsumerState<PodcastVideoScreen> createState() => _PodcastVideoScreenState();
}

class _PodcastVideoScreenState extends ConsumerState<PodcastVideoScreen>
    with SingleTickerProviderStateMixin {
  final _playerKey = GlobalKey<YouTubeWebViewPlayerState>();
  late final TabController _tabController;
  late final PageController _pageController;
  bool _loading = true;
  int? _playerError; // IFrame API error code (101/150 = embedding disabled)

  // Like / Dislike optimistic states
  bool? _liked;
  bool? _disliked;

  @override
  void initState() {
    super.initState();
    // Pause background audio when opening video
    ref.read(audioPlayerServiceProvider).pause();
    _tabController = TabController(length: 3, vsync: this);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _seekVideo(Duration pos) {
    _playerKey.currentState?.seekTo(pos.inSeconds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Jumped to ${_formatDuration(pos)}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openInYouTube() async {
    final uri = Uri.parse(
        'https://www.youtube.com/watch?v=${widget.episode.videoId}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _shareEpisode() {
    ShareSheet.showLinks(
      context,
      type: 'song',
      id: widget.episode.videoId,
      title: widget.episode.title,
      shareText: (url) => 'Check out "${widget.episode.title}" on Inzx: $url',
    );
  }

  Future<void> _toggleLike() async {
    final authState = ref.read(ytMusicAuthStateProvider);
    if (!authState.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to YouTube Music to like')),
      );
      return;
    }
    final isLikedNow = _liked ?? false;
    final newLiked = !isLikedNow;
    setState(() {
      _liked = newLiked;
      if (newLiked) _disliked = false;
    });

    final action = ref.read(ytMusicLikeActionProvider);
    final ok = newLiked
        ? await action.like(widget.episode.videoId)
        : await action.unlike(widget.episode.videoId);
    if (!ok && mounted) {
      setState(() => _liked = isLikedNow);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update like')),
      );
    }
  }

  Future<void> _toggleDislike() async {
    final authState = ref.read(ytMusicAuthStateProvider);
    if (!authState.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to YouTube Music to dislike')),
      );
      return;
    }
    final isDislikedNow = _disliked ?? false;
    final newDisliked = !isDislikedNow;
    setState(() {
      _disliked = newDisliked;
      if (newDisliked) _liked = false;
    });

    final action = ref.read(ytMusicLikeActionProvider);
    final ok = newDisliked
        ? await action.dislike(widget.episode.videoId)
        : await action.undislike(widget.episode.videoId);
    if (!ok && mounted) {
      setState(() => _disliked = isDislikedNow);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update dislike')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = ref.watch(effectiveAccentColorProvider);
    final textColor = isDark ? Colors.white : colorScheme.onSurface;
    final secondary = textColor.withValues(alpha: 0.6);

    final isLiked = _liked ?? false;
    final isDisliked = _disliked ?? false;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          ep.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share',
            onPressed: _shareEpisode,
          ),
        ],
      ),
      body: Column(
        children: [
          // 16:9 Embedded YouTube Player (official IFrame API + origin trick)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                YouTubeWebViewPlayer(
                  key: _playerKey,
                  videoId: widget.episode.videoId,
                  autoPlay: true,
                  onReady: () {
                    if (mounted) setState(() => _loading = false);
                  },
                  onError: (code) {
                    if (mounted) setState(() => _playerError = code);
                  },
                ),
                if (_loading && _playerError == null)
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: accent,
                      ),
                    ),
                  ),
                // Embedding disabled by the uploader (101/150) — offer YouTube.
                if (_playerError == 101 || _playerError == 150)
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.smart_display_outlined,
                              color: Colors.white70, size: 40),
                          const SizedBox(height: 10),
                          const Text(
                            "This episode can't be embedded.",
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openInYouTube,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Open in YouTube'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Header Info & Like/Unlike Action Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Title and Podcast name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ep.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (ep.subtitle != null && ep.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          ep.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: secondary, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Like & Dislike pill buttons
                Container(
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Like button
                      IconButton(
                        onPressed: _toggleLike,
                        iconSize: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                        icon: Icon(
                          isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                          color: isLiked ? accent : textColor,
                        ),
                        tooltip: 'Like',
                      ),
                      Container(
                        height: 16,
                        width: 1,
                        color: textColor.withValues(alpha: 0.2),
                      ),
                      // Dislike button
                      IconButton(
                        onPressed: _toggleDislike,
                        iconSize: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                        icon: Icon(
                          isDisliked
                              ? Icons.thumb_down_rounded
                              : Icons.thumb_down_outlined,
                          color: isDisliked ? accent : textColor,
                        ),
                        tooltip: 'Dislike',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Swipeable Navigation Bar: EPISODE DETAILS | COMMENTS | RELATED
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: textColor.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: accent,
              unselectedLabelColor: secondary,
              indicatorColor: accent,
              indicatorWeight: 2,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              onTap: (index) {
                if (_pageController.hasClients) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
              tabs: const [
                Tab(text: 'DETAILS'),
                Tab(text: 'COMMENTS'),
                Tab(text: 'RELATED'),
              ],
            ),
          ),

          // Swipeable Content Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                if (_tabController.index != index) {
                  _tabController.animateTo(index);
                }
              },
              children: [
                _buildDetailsTab(ep, textColor, secondary, accent),
                _buildCommentsTab(ep, textColor, secondary, accent),
                _buildRelatedTab(ep, textColor, secondary, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 1: Episode Details & Interactive Notes / Chapter Timestamps
  Widget _buildDetailsTab(
    Episode ep,
    Color textColor,
    Color secondary,
    Color accent,
  ) {
    final detailsAsync = ref.watch(ytMusicEpisodeDetailsProvider(ep.videoId));

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ep.title,
            style: TextStyle(
              color: textColor,
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (ep.subtitle != null && ep.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [ep.subtitle, ep.durationText]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' • '),
              style: TextStyle(color: secondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: textColor.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          Text(
            'Episode Notes & Chapters',
            style: TextStyle(
              color: textColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          detailsAsync.when(
            loading: () {
              if (ep.description != null && ep.description!.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichDescription(
                      text: ep.description!,
                      color: secondary,
                      linkColor: accent,
                      maxLines: null,
                      onLink: _openLink,
                      onTimestamp: _seekVideo,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: accent,
                  ),
                ),
              );
            },
            error: (_, _) {
              final desc =
                  ep.description ?? 'No notes available for this episode.';
              return RichDescription(
                text: desc,
                color: secondary,
                linkColor: accent,
                maxLines: null,
                onLink: _openLink,
                onTimestamp: _seekVideo,
              );
            },
            data: (data) {
              final fullDesc =
                  data?['description'] as String? ?? ep.description;
              if (fullDesc == null || fullDesc.isEmpty) {
                return Text(
                  'No notes available.',
                  style: TextStyle(color: secondary, fontSize: 13),
                );
              }
              return RichDescription(
                text: fullDesc,
                color: secondary,
                linkColor: accent,
                maxLines: null,
                onLink: _openLink,
                onTimestamp: _seekVideo,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Tab 2: Comments Tab
  Widget _buildCommentsTab(
    Episode ep,
    Color textColor,
    Color secondary,
    Color accent,
  ) {
    final commentsAsync = ref.watch(ytMusicCommentsProvider(ep.videoId));

    return commentsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: accent,
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Couldn\'t load comments.\n$e',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13),
          ),
        ),
      ),
      data: (comments) {
        if (comments.isEmpty) {
          return Center(
            child: Text(
              'No comments found for this episode.',
              style: TextStyle(color: secondary, fontSize: 13),
            ),
          );
        }
        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: comments.length,
          separatorBuilder: (_, _) => Divider(
            height: 20,
            color: textColor.withValues(alpha: 0.06),
          ),
          itemBuilder: (context, index) {
            final c = comments[index];
            final author = c['author'] as String? ?? 'User';
            final text = c['text'] as String? ?? '';
            final time = c['time'] as String? ?? '';
            final likes = c['likes'] as String? ?? '';
            final thumb = c['authorThumbnail'] as String?;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: textColor.withValues(alpha: 0.1),
                  backgroundImage:
                      thumb != null ? CachedNetworkImageProvider(thumb) : null,
                  child: thumb == null
                      ? Text(
                          author.isNotEmpty ? author[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              time,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      RichDescription(
                        text: text,
                        color: textColor.withValues(alpha: 0.85),
                        linkColor: accent,
                        maxLines: null,
                        onLink: _openLink,
                        onTimestamp: _seekVideo,
                      ),
                      if (likes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.thumb_up_alt_outlined,
                              size: 13,
                              color: secondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              likes,
                              style: TextStyle(color: secondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Tab 3: Related Episodes / Shows Tab
  Widget _buildRelatedTab(
    Episode ep,
    Color textColor,
    Color secondary,
    Color accent,
  ) {
    final relatedAsync = ref.watch(ytMusicWatchRelatedProvider(ep.videoId));

    return relatedAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: accent,
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Couldn\'t load related content.\n$e',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13),
          ),
        ),
      ),
      data: (content) {
        if (content.isEmpty) {
          return Center(
            child: Text(
              'No related content available.',
              style: TextStyle(color: secondary, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: content.shelves.length,
          itemBuilder: (context, shelfIdx) {
            final shelf = content.shelves[shelfIdx];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    shelf.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...shelf.items.map((item) {
                  final itemThumb = item.thumbnailUrl;
                  return InkWell(
                    onTap: () {
                      if (item.itemType == HomeShelfItemType.podcast &&
                          item.navigationId != null) {
                        PodcastScreen.open(
                          context,
                          podcastId: item.navigationId!,
                          title: item.title,
                          thumbnailUrl: itemThumb,
                        );
                      } else if (item.videoId != null) {
                        // Open this video episode in PodcastVideoScreen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PodcastVideoScreen(
                              episode: Episode(
                                videoId: item.videoId!,
                                title: item.title,
                                podcastTitle: item.subtitle ?? '',
                                subtitle: item.subtitle,
                                thumbnailUrl: itemThumb,
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: itemThumb != null
                                  ? CachedNetworkImage(
                                      imageUrl: itemThumb,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: textColor.withValues(alpha: 0.1),
                                      child: Icon(
                                        Icons.podcasts_rounded,
                                        color: secondary,
                                        size: 24,
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
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (item.subtitle != null &&
                                    item.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }
}

