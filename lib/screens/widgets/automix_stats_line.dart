import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';

import '../../providers/providers.dart';
import '../../services/automix/automix_service.dart';

/// Automix's line in stats for nerds, under the stream stats (BitChord's
/// layout): both songs' analysis while it waits, then the planned mix.
/// Refreshes once a second; empty while Automix or stats for nerds is off.
class AutomixStatsLine extends ConsumerStatefulWidget {
  const AutomixStatsLine({
    super.key,
    required this.color,
    this.fontSize = 10.5,
    this.width,
  });

  final Color color;
  final double fontSize;
  final double? width;

  @override
  ConsumerState<AutomixStatsLine> createState() => _AutomixStatsLineState();
}

class _AutomixStatsLineState extends ConsumerState<AutomixStatsLine> {
  Timer? _timer;
  String? _line;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = ref.read(playbackStateProvider).valueOrNull;
    final current = state?.currentTrack;
    String? line;
    if (current != null && (state?.showNerdStats ?? false)) {
      final queue = state!.queue;
      final i = state.currentIndex;
      final next = (i >= 0 && i + 1 < queue.length) ? queue[i + 1].id : null;
      line = await AutomixService.instance.statsLine(current.id, next);
    }
    if (mounted && line != _line) setState(() => _line = line);
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    if (line == null || line.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w500,
      color: widget.color,
      letterSpacing: 0.2,
    );
    return SizedBox(
      height: widget.fontSize * 1.6,
      width: widget.width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: line, style: style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          if (painter.width <= constraints.maxWidth) {
            return Center(child: Text(line, style: style, maxLines: 1));
          }
          return Marquee(
            text: line,
            style: style,
            blankSpace: 40,
            velocity: 25,
            pauseAfterRound: const Duration(seconds: 2),
          );
        },
      ),
    );
  }
}
