import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/explore_page.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../widgets/album_screen.dart';
import '../widgets/artist_screen.dart';
import '../widgets/desktop_track_grid.dart'
    show DesktopHomeSkeleton, cleanShelfSubtitle;
import '../widgets/now_playing_screen.dart';
import '../widgets/playlist_screen.dart';
import '../widgets/podcast_screen.dart';

const double _kPageGutter = 32;
const double _kCardWidth = 180;
const double _kVideoCardWidth = 300;
const double _kListRowHeight = 64;
const double _kListColumnWidth = 400;
const double _kMoodTileWidth = 200;
const double _kMoodTileHeight = 48;
const int _kRowsPerColumn = 4;

typedef _ExploreKey = ({String browseId, String? params});

final _explorePageProvider = FutureProvider.family<ExplorePage?, _ExploreKey>((
  ref,
  key,
) {
  return ref
      .watch(innerTubeServiceProvider)
      .getExplorePage(browseId: key.browseId, params: key.params);
});

void _openLink(BuildContext context, ExploreLink link) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DesktopExploreDetailScreen(
        title: link.title,
        browseId: link.browseId,
        params: link.params,
      ),
    ),
  );
}

void _openItem(BuildContext context, WidgetRef ref, HomeShelfItem item) {
  final videoId = item.videoId;
  final track =
      item.toTrack() ??
      (videoId != null
          ? Track(
              id: videoId,
              title: item.title,
              artist: item.subtitle?.split('•').first.trim() ?? '',
              artistId: item.artistId ?? '',
              thumbnailUrl: item.thumbnailUrl,
              duration: item.duration ?? Duration.zero,
            )
          : null);
  if (track != null) {
    ref.read(audioPlayerServiceProvider).playTrack(track, enableRadio: true);
    ref.read(recentlyPlayedProvider.notifier).addTrack(track);
    NowPlayingScreen.show(context);
    return;
  }

  final id = item.navigationId ?? item.id;
  if (item.itemType == HomeShelfItemType.podcast || id.startsWith('MPSP')) {
    PodcastScreen.open(
      context,
      podcastId: item.playlistId ?? id,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
    );
  } else if (item.itemType == HomeShelfItemType.artist) {
    ArtistScreen.open(
      context,
      artistId: id,
      name: item.title,
      thumbnailUrl: item.thumbnailUrl,
    );
  } else if (item.itemType == HomeShelfItemType.album) {
    AlbumScreen.open(
      context,
      albumId: id,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
    );
  } else {
    PlaylistScreen.open(
      context,
      playlistId: item.playlistId ?? id,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
    );
  }
}

/// YouTube Music's Explore page, in the sidebar in place of Songs.
class DesktopExploreTab extends StatelessWidget {
  const DesktopExploreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ExploreBody(
      key: PageStorageKey('explore'),
      browseId: 'FEmusic_explore',
    );
  }
}

/// A page linked from Explore: new releases, charts, moods or one mood.
class DesktopExploreDetailScreen extends StatelessWidget {
  const DesktopExploreDetailScreen({
    super.key,
    required this.title,
    required this.browseId,
    this.params,
  });

  final String title;
  final String browseId;
  final String? params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _ExploreBody(browseId: browseId, params: params),
    );
  }
}

/// Finds an Explore link by its name ("Feel good", "Podcasts") among the
/// links on Explore and on Moods & genres, ignoring case and punctuation.
final _exploreLinkByNameProvider = FutureProvider.family<ExploreLink?, String>((
  ref,
  name,
) async {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final wanted = norm(name);
  for (final browseId in const [
    'FEmusic_explore',
    'FEmusic_moods_and_genres',
  ]) {
    final page = await ref.watch(
      _explorePageProvider((browseId: browseId, params: null)).future,
    );
    if (page == null) continue;
    for (final link in [
      ...page.topLinks,
      for (final section in page.sections) ...section.links,
    ]) {
      if (norm(link.title) == wanted) return link;
    }
  }
  return null;
});

/// The Explore page behind one of the home's mood chips, the same page its
/// tile on Explore opens. If Explore has no link by that name, offers a
/// search instead.
class DesktopExploreMoodScreen extends ConsumerWidget {
  const DesktopExploreMoodScreen({
    super.key,
    required this.title,
    required this.linkName,
    required this.onSearch,
  });

  /// The chip's label, shown as the page title.
  final String title;

  /// The link's name on Explore, where it differs ("Relax" is "Chill").
  final String linkName;

  /// Runs the search the chip used to, when Explore has no such page.
  final VoidCallback onSearch;

  static Future<void> open(
    BuildContext context, {
    required String title,
    String? linkName,
    required VoidCallback onSearch,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DesktopExploreMoodScreen(
          title: title,
          linkName: linkName ?? title,
          onSearch: onSearch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(_exploreLinkByNameProvider(linkName));
    final found = link.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(found?.title ?? title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: link.isLoading
          ? const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: DesktopHomeSkeleton(),
            )
          : found != null
          ? _ExploreBody(browseId: found.browseId, params: found.params)
          : Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      // A failed load stays cached, so reload the pages too.
                      for (final browseId in const [
                        'FEmusic_explore',
                        'FEmusic_moods_and_genres',
                      ]) {
                        ref.invalidate(
                          _explorePageProvider((
                            browseId: browseId,
                            params: null,
                          )),
                        );
                      }
                      ref.invalidate(_exploreLinkByNameProvider(linkName));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onSearch();
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: Text('Search for $title'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ExploreBody extends ConsumerWidget {
  const _ExploreBody({super.key, required this.browseId, this.params});

  final String browseId;
  final String? params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (browseId: browseId, params: params);
    return ref
        .watch(_explorePageProvider(key))
        .when(
          loading: () => const SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: DesktopHomeSkeleton(),
          ),
          error: (_, _) => _retry(ref, key),
          data: (page) {
            if (page == null) return _retry(ref, key);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                _kPageGutter,
                12,
                _kPageGutter,
                32,
              ),
              children: [
                if (page.topLinks.isNotEmpty) ...[
                  _TopLinks(links: page.topLinks),
                  const SizedBox(height: 36),
                ],
                for (final section in page.sections) ...[
                  _SectionView(section: section),
                  const SizedBox(height: 36),
                ],
              ],
            );
          },
        );
  }

  Widget _retry(WidgetRef ref, _ExploreKey key) {
    return Center(
      child: TextButton.icon(
        onPressed: () => ref.invalidate(_explorePageProvider(key)),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

class _TopLinks extends StatelessWidget {
  const _TopLinks({required this.links});

  final List<ExploreLink> links;

  IconData _icon(String? type) => switch (type) {
    'MUSIC_NEW_RELEASE' => Icons.new_releases_outlined,
    'TRENDING_UP' => Icons.trending_up_rounded,
    'STICKER_EMOTICON' ||
    'SENTIMENT_SATISFIED' => Icons.sentiment_satisfied_alt_rounded,
    'BROADCAST' || 'PODCAST' => Icons.podcasts_rounded,
    _ => Icons.explore_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    return Row(
      children: [
        for (final (index, link) in links.indexed) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: base.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openLink(context, link),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: 18),
                      Icon(_icon(link.iconType), color: base),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          link.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: base,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final ExploreSection section;

  bool get _isTrackList => section.items.every(
    (item) =>
        item.itemType == HomeShelfItemType.song ||
        item.itemType == HomeShelfItemType.podcast && item.videoId != null,
  );

  bool get _isVideos =>
      section.items.isNotEmpty &&
      section.items.every((item) => item.itemType == HomeShelfItemType.video);

  @override
  Widget build(BuildContext context) {
    if (section.links.isNotEmpty) {
      return section.isGrid
          ? _Heading(
              section: section,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final link in section.links) _MoodTile(link: link),
                ],
              ),
            )
          : _HorizontalSection(
              section: section,
              height: _kRowsPerColumn * (_kMoodTileHeight + 12),
              itemExtent: _kMoodTileWidth + 12,
              itemCount: (section.links.length / _kRowsPerColumn).ceil(),
              itemBuilder: (context, column) => Column(
                children: [
                  for (
                    var i = column * _kRowsPerColumn;
                    i < (column + 1) * _kRowsPerColumn &&
                        i < section.links.length;
                    i++
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MoodTile(link: section.links[i]),
                    ),
                ],
              ),
            );
    }

    if (_isTrackList) {
      if (section.isGrid || section.browseId == null && section.title.isEmpty) {
        return _Heading(
          section: section,
          child: Column(
            children: [
              for (final (index, item) in section.items.indexed)
                _TrackRow(item: item, rank: index + 1),
            ],
          ),
        );
      }
      return _HorizontalSection(
        section: section,
        height: _kRowsPerColumn * _kListRowHeight,
        itemExtent: _kListColumnWidth + 16,
        itemCount: (section.items.length / _kRowsPerColumn).ceil(),
        itemBuilder: (context, column) => SizedBox(
          width: _kListColumnWidth,
          child: Column(
            children: [
              for (
                var i = column * _kRowsPerColumn;
                i < (column + 1) * _kRowsPerColumn && i < section.items.length;
                i++
              )
                _TrackRow(item: section.items[i], rank: i + 1),
            ],
          ),
        ),
      );
    }

    final cardWidth = _isVideos ? _kVideoCardWidth : _kCardWidth;
    final cardHeight = (_isVideos ? cardWidth * 9 / 16 : cardWidth) + 68;
    if (section.isGrid) {
      return _Heading(
        section: section,
        child: Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final item in section.items)
              _ItemCard(item: item, width: cardWidth, height: cardHeight),
          ],
        ),
      );
    }
    return _HorizontalSection(
      section: section,
      height: cardHeight,
      itemExtent: cardWidth + 16,
      itemCount: section.items.length,
      itemBuilder: (context, index) => _ItemCard(
        item: section.items[index],
        width: cardWidth,
        height: cardHeight,
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.section, required this.child, this.trailing});

  final ExploreSection section;
  final Widget child;
  final List<Widget>? trailing;

  void _openMore(BuildContext context) {
    final browseId = section.browseId!;
    if (browseId.startsWith('VL')) {
      PlaylistScreen.open(context, playlistId: browseId, title: section.title);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DesktopExploreDetailScreen(
            title: section.title,
            browseId: browseId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: base,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (section.browseId != null)
                OutlinedButton(
                  onPressed: () => _openMore(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: const StadiumBorder(),
                    foregroundColor: base,
                    side: BorderSide(color: base.withValues(alpha: 0.25)),
                  ),
                  child: const Text('More'),
                ),
              ...?trailing,
            ],
          ),
          const SizedBox(height: 16),
        ],
        child,
      ],
    );
  }
}

/// A heading with back and forward arrows over one row that scrolls sideways.
class _HorizontalSection extends StatefulWidget {
  const _HorizontalSection({
    required this.section,
    required this.height,
    required this.itemExtent,
    required this.itemCount,
    required this.itemBuilder,
  });

  final ExploreSection section;
  final double height;
  final double itemExtent;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_HorizontalSection> createState() => _HorizontalSectionState();
}

class _HorizontalSectionState extends State<_HorizontalSection> {
  final ScrollController _controller = ScrollController(
    keepScrollOffset: false,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.85).clamp(
          0.0,
          position.maxScrollExtent,
        );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;

    Widget arrow(IconData icon, int direction) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton.outlined(
        style: IconButton.styleFrom(
          side: BorderSide(color: base.withValues(alpha: 0.25)),
          shape: const CircleBorder(),
        ),
        iconSize: 20,
        onPressed: () => _page(direction),
        icon: Icon(icon, color: base),
      ),
    );

    return _Heading(
      section: widget.section,
      trailing: [
        arrow(Icons.chevron_left_rounded, -1),
        arrow(Icons.chevron_right_rounded, 1),
      ],
      child: SizedBox(
        height: widget.height,
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemExtent: widget.itemExtent,
          itemCount: widget.itemCount,
          itemBuilder: (context, index) => Align(
            alignment: Alignment.topLeft,
            child: widget.itemBuilder(context, index),
          ),
        ),
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.link});

  final ExploreLink link;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    final stripe = link.stripeColor;
    return SizedBox(
      width: _kMoodTileWidth,
      height: _kMoodTileHeight,
      child: Material(
        color: base.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openLink(context, link),
          child: Row(
            children: [
              Container(
                width: 6,
                color: stripe != null
                    ? Color(stripe)
                    : base.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  link.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: base,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends ConsumerWidget {
  const _TrackRow({required this.item, required this.rank});

  final HomeShelfItem item;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openItem(context, ref, item),
      child: SizedBox(
        height: _kListRowHeight,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _Thumbnail(url: item.thumbnailUrl, size: 48, base: base),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: base,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: base,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      cleanShelfSubtitle(item.subtitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: base.withValues(alpha: 0.6),
                        fontSize: 13,
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
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.item,
    required this.width,
    required this.height,
  });

  final HomeShelfItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    final isArtist = item.itemType == HomeShelfItemType.artist;
    final artHeight = height - 68;

    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openItem(context, ref, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(isArtist ? width / 2 : 6),
              child: SizedBox(
                width: width,
                height: artHeight,
                child: _Thumbnail(url: item.thumbnailUrl, base: base),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: base,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.subtitle != null)
              Text(
                cleanShelfSubtitle(item.subtitle!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: base.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.base, this.size});

  final String? url;
  final Color base;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: base.withValues(alpha: 0.1),
      child: Icon(Icons.music_note_rounded, color: base.withValues(alpha: 0.5)),
    );
    final imageUrl = url;
    if (imageUrl == null) return fallback;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => fallback,
      placeholder: (_, _) => fallback,
    );
  }
}
