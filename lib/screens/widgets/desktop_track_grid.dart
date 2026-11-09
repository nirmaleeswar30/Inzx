import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import 'now_playing_screen.dart';
import 'track_artwork_view.dart';
import 'track_options_sheet.dart';

const double _kRowHeight = 80;
const int _kRowsPerColumn = 4;

/// The parser joins every text run with a bullet, including the "&" and ","
/// between artist names.
String cleanShelfSubtitle(String subtitle) => subtitle
    .replaceAll(RegExp(r'\s*•\s*&\s*•\s*'), ' & ')
    .replaceAll(RegExp(r'\s*•\s*,\s*•\s*'), ', ');

/// YouTube Music's Quick picks: rows of songs four deep, in columns that page
/// sideways, with Play all and arrows in the heading.
class DesktopTrackGridShelf extends ConsumerStatefulWidget {
  const DesktopTrackGridShelf({super.key, required this.shelf});

  final HomeShelf shelf;

  @override
  ConsumerState<DesktopTrackGridShelf> createState() =>
      _DesktopTrackGridShelfState();
}

class _DesktopTrackGridShelfState extends ConsumerState<DesktopTrackGridShelf> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Rebuilds only to dim an arrow at either end of the row.
  void _onScroll() => setState(() {});

  bool get _atStart =>
      !_controller.hasClients ||
      _controller.position.pixels <= _controller.position.minScrollExtent;

  bool get _atEnd =>
      _controller.hasClients &&
      _controller.position.pixels >= _controller.position.maxScrollExtent;

  void _page(int direction) {
    final position = _controller.position;
    _controller.animateTo(
      (position.pixels + direction * position.viewportDimension).clamp(
        0.0,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _play(BuildContext context, List<Track> tracks, int index) {
    final player = ref.read(audioPlayerServiceProvider);
    NowPlayingScreen.show(context);
    player.playQueue(tracks, startIndex: index);
    ref.read(recentlyPlayedProvider.notifier).addTrack(tracks[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;

    final rows = <({HomeShelfItem item, Track track})>[
      for (final item in widget.shelf.items)
        if (item.toTrack() case final track?) (item: item, track: track),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final tracks = [for (final row in rows) row.track];

    Widget arrow(IconData icon, int direction, bool enabled) => Padding(
      padding: const EdgeInsets.only(left: 12),
      child: IconButton.outlined(
        style: IconButton.styleFrom(
          side: BorderSide(color: base.withValues(alpha: enabled ? 0.25 : 0.1)),
          shape: const CircleBorder(),
        ),
        iconSize: 20,
        onPressed: enabled ? () => _page(direction) : null,
        icon: Icon(icon, color: base.withValues(alpha: enabled ? 1 : 0.3)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.shelf.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: base,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => _play(context, tracks, 0),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: const StadiumBorder(),
                  foregroundColor: base,
                  side: BorderSide(color: base.withValues(alpha: 0.25)),
                ),
                child: const Text('Play all'),
              ),
              arrow(Icons.chevron_left_rounded, -1, !_atStart),
              arrow(Icons.chevron_right_rounded, 1, !_atEnd),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 3
                  : (constraints.maxWidth >= 720 ? 2 : 1);
              final columnCount = (rows.length / _kRowsPerColumn).ceil();
              return SizedBox(
                height: _kRowsPerColumn * _kRowHeight,
                child: ListView.builder(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  itemExtent: constraints.maxWidth / columns,
                  itemCount: columnCount,
                  itemBuilder: (context, column) {
                    final first = column * _kRowsPerColumn;
                    final last = (first + _kRowsPerColumn).clamp(
                      0,
                      rows.length,
                    );
                    return Column(
                      children: [
                        for (var i = first; i < last; i++)
                          _TrackRow(
                            item: rows[i].item,
                            track: rows[i].track,
                            base: base,
                            onTap: () => _play(context, tracks, i),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({
    required this.item,
    required this.track,
    required this.base,
    required this.onTap,
  });

  final HomeShelfItem item;
  final Track track;
  final Color base;
  final VoidCallback onTap;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final base = widget.base;
    final isCurrent = ref.watch(currentTrackIdProvider) == track.id;
    final accent = ref.watch(effectiveAccentColorProvider);
    final subtitle = widget.item.subtitle;

    return SizedBox(
      height: _kRowHeight,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          onSecondaryTap: () => TrackOptionsSheet.show(context, track),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  TrackArtworkView(
                    track: track,
                    width: 60,
                    height: 60,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  if (_hovered) ...[
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? accent : base,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        cleanShelfSubtitle(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: base.withValues(alpha: 0.65),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_hovered)
                IconButton(
                  iconSize: 20,
                  onPressed: () => TrackOptionsSheet.show(context, track),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: base.withValues(alpha: 0.8),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
