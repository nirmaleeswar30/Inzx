import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/design_system/design_system.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../providers/providers.dart';
import '../../services/listening_stats_service.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'package:inzx/core/utils/platform_utils.dart';

/// "12h 34m", "45m", "30s".
String formatListening(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) {
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${d.inHours}h' : '${d.inHours}h ${minutes}m';
  }
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _hourLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour < 12 ? 'AM' : 'PM'}';
}

String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// What kind of listener the hours say you are.
(String, IconData) _listenerType(int? peakHour) {
  if (peakHour == null) return ('Listener', Iconsax.headphones);
  if (peakHour >= 5 && peakHour < 10) {
    return ('Early bird', Iconsax.sun_fog);
  }
  if (peakHour >= 10 && peakHour < 17) {
    return ('Daytime listener', Iconsax.sun_1);
  }
  if (peakHour >= 17 && peakHour < 22) {
    return ('Evening listener', Iconsax.cloud_sunny);
  }
  return ('Night owl', Iconsax.moon);
}

/// The colours every card of the stats shares.
class _Palette {
  _Palette(BuildContext context, this.accent)
    : isDark = Theme.of(context).brightness == Brightness.dark;

  final bool isDark;
  final Color accent;

  Color get text => isDark ? Colors.white : InzxColors.textPrimary;
  Color get secondary =>
      isDark ? Colors.white.withValues(alpha: 0.6) : InzxColors.textSecondary;
  Color get card => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.92);
  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);
  Color get track => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);

  /// A deeper shade of the accent for gradients.
  Color get accentDeep {
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.08, 0.5))
        .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
        .toColor();
  }
}

/// The whole statistics page body: the period switch and every section.
/// Used by the Statistics screen and the Library tab.
class ListeningStatsView extends ConsumerStatefulWidget {
  const ListeningStatsView({super.key, this.padding});

  final EdgeInsets? padding;

  @override
  ConsumerState<ListeningStatsView> createState() => _ListeningStatsViewState();
}

class _ListeningStatsViewState extends ConsumerState<ListeningStatsView> {
  StatsPeriod _period = StatsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(listeningStatsProvider);
    final accent = ref.watch(effectiveAccentColorProvider);
    final palette = _Palette(context, accent);
    final summary = stats.summarize(_period);
    final everything = _period == StatsPeriod.allTime
        ? summary
        : stats.summarize(StatsPeriod.allTime, limit: 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final gap = wide ? 20.0 : 16.0;
        final padding =
            widget.padding ??
            EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 120);

        final List<Widget> sections;
        if (everything.isEmpty) {
          sections = [_EmptyState(palette: palette, wholeLibrary: true)];
        } else if (summary.isEmpty) {
          sections = [_EmptyState(palette: palette, wholeLibrary: false)];
        } else {
          final activity = _ActivityCard(summary: summary, palette: palette);
          final clock = _ClockCard(summary: summary, palette: palette);
          final streak = _StreakCard(summary: summary, palette: palette);
          sections = [
            _HeroCard(summary: summary, palette: palette),
            SizedBox(height: gap),
            // Fixed heights: the clock's dial fits the card rather than
            // the card growing to a square and stretching its neighbours.
            if (wide)
              SizedBox(
                height: 290,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: activity),
                    SizedBox(width: gap),
                    Expanded(flex: 3, child: clock),
                    SizedBox(width: gap),
                    Expanded(flex: 3, child: streak),
                  ],
                ),
              )
            else ...[
              activity,
              SizedBox(height: gap),
              SizedBox(
                height: 260,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: clock),
                    SizedBox(width: gap),
                    Expanded(child: streak),
                  ],
                ),
              ),
            ],
            if (summary.topArtists.isNotEmpty) ...[
              SizedBox(height: gap * 1.5),
              _TopArtistFeature(
                artist: summary.topArtists.first,
                period: _period,
                palette: palette,
              ),
              if (summary.topArtists.length > 1) ...[
                SizedBox(height: gap),
                _ArtistRow(
                  artists: summary.topArtists.skip(1).take(14).toList(),
                  palette: palette,
                ),
              ],
            ],
            if (summary.topTracks.isNotEmpty) ...[
              SizedBox(height: gap * 1.5),
              _TopSongs(
                tracks: summary.topTracks.take(wide ? 12 : 10).toList(),
                period: _period,
                palette: palette,
                columns: wide ? 2 : 1,
              ),
            ],
            if (summary.topAlbums.isNotEmpty) ...[
              SizedBox(height: gap * 1.5),
              _AlbumRow(
                albums: summary.topAlbums.take(12).toList(),
                palette: palette,
              ),
            ],
            SizedBox(height: gap * 1.5),
            _Insights(summary: summary, palette: palette, wide: wide),
            if (everything.firstDay case final first?) ...[
              SizedBox(height: gap),
              Center(
                child: Text(
                  'Counting since ${_dateLabel(first)} ${first.year}',
                  style: TextStyle(fontSize: 12, color: palette.secondary),
                ),
              ),
            ],
          ];
        }

        return ListView(
          padding: padding,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PeriodSwitch(
                      value: _period,
                      palette: palette,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                    SizedBox(height: gap),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      child: Column(
                        key: ValueKey(_period),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sections,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- Period switch --------------------------------------------------------

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final StatsPeriod value;
  final _Palette palette;
  final ValueChanged<StatsPeriod> onChanged;

  static const _labels = {
    StatsPeriod.week: 'Week',
    StatsPeriod.month: 'Month',
    StatsPeriod.year: 'Year',
    StatsPeriod.allTime: 'All time',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final period in StatsPeriod.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: period == value ? palette.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _labels[period]!,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: period == value
                          ? _onColor(palette.accent)
                          : palette.secondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color _onColor(Color background) =>
    background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

// ---- Cards ------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final _Palette palette;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.palette, {this.trailing});

  final String title;
  final _Palette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: palette.text,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary, required this.palette});

  final ListeningSummary summary;
  final _Palette palette;

  String get _caption => switch (summary.period) {
    StatsPeriod.week => 'This week you listened for',
    StatsPeriod.month => 'In the last 30 days you listened for',
    StatsPeriod.year => 'This past year you listened for',
    StatsPeriod.allTime => 'You’ve listened for',
  };

  String get _versus => switch (summary.period) {
    StatsPeriod.week => 'vs the week before',
    StatsPeriod.month => 'vs the 30 days before',
    StatsPeriod.year => 'vs the year before',
    StatsPeriod.allTime => '',
  };

  @override
  Widget build(BuildContext context) {
    final change = summary.change;
    final hours = summary.totalMs / 3600000;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.accent, palette.accentDeep],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _WavesPainter(Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _caption,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatListening(summary.totalMs),
                      style: const TextStyle(
                        fontSize: 56,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (hours >= 1)
                    Text(
                      hours >= 24
                          ? 'That’s ${(hours / 24).toStringAsFixed(1)} days of music'
                          : '${(summary.totalMs / 60000).round()} minutes of music',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeroChip(
                        icon: Icons.play_arrow_rounded,
                        label: '${summary.plays} plays',
                      ),
                      _HeroChip(
                        icon: Icons.music_note_rounded,
                        label: '${summary.uniqueTracks} songs',
                      ),
                      _HeroChip(
                        icon: Icons.person_rounded,
                        label: '${summary.uniqueArtists} artists',
                      ),
                      if (change != null)
                        _HeroChip(
                          icon: change >= 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          label:
                              '${change >= 0 ? '+' : '−'}${(change.abs() * 100).round()}% $_versus',
                          strong: true,
                        ),
                    ],
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

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: strong ? 0.26 : 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft sound waves across the hero card.
class _WavesPainter extends CustomPainter {
  _WavesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 5; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.07 + i * 0.015);
      final path = Path();
      final baseline = size.height * (0.55 + i * 0.09);
      final amplitude = 14.0 + i * 6;
      final wavelength = size.width / (1.4 + i * 0.25);
      path.moveTo(0, baseline);
      for (var x = 0.0; x <= size.width; x += 6) {
        path.lineTo(
          x,
          baseline + math.sin((x / wavelength) * 2 * math.pi + i) * amplitude,
        );
      }
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.12),
      size.height * 0.55,
      Paint()..color = color.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.color != color;
}

// ---- Activity ---------------------------------------------------------------

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.summary, required this.palette});

  final ListeningSummary summary;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final buckets = summary.buckets;
    final daily = buckets.isNotEmpty && !buckets.first.isMonth;
    final average = daily
        ? summary.totalMs ~/ math.max(1, summary.days)
        : summary.totalMs ~/ math.max(1, buckets.length);
    StatsBucket? peak;
    for (final b in buckets) {
      if (b.ms > 0 && (peak == null || b.ms > peak.ms)) peak = b;
    }

    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listening activity',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatListening(average)} a ${daily ? 'day' : 'month'} on average'
            '${peak == null ? '' : ' · most on ${daily ? _dateLabel(peak.start) : '${_months[peak.start.month - 1]} ${peak.start.year}'}'}',
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: _BarChart(buckets: buckets, palette: palette),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.buckets, required this.palette});

  final List<StatsBucket> buckets;
  final _Palette palette;

  String _label(StatsBucket b, int index) {
    if (b.isMonth) return _months[b.start.month - 1].substring(0, 1);
    if (buckets.length <= 7) {
      return _weekdays[b.start.weekday - 1].substring(0, 3);
    }
    // A month of days: label every fifth, and today.
    return (index % 5 == 0 || b.isCurrent) ? '${b.start.day}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = buckets.fold<int>(0, (m, b) => math.max(m, b.ms));
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = buckets.length;
        final slot = constraints.maxWidth / math.max(1, count);
        final barWidth = (slot * (count > 14 ? 0.62 : 0.5)).clamp(3.0, 28.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, b) in buckets.indexed)
              SizedBox(
                width: slot,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message:
                          '${b.isMonth ? '${_months[b.start.month - 1]} ${b.start.year}' : _dateLabel(b.start)}: ${formatListening(b.ms)}',
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: maxMs == 0 ? 0 : b.ms / maxMs,
                        ),
                        duration: Duration(milliseconds: 500 + i * 12),
                        curve: Curves.easeOutCubic,
                        builder: (context, fraction, _) {
                          final height = math.max(
                            4.0,
                            fraction * (constraints.maxHeight - 26),
                          );
                          return Container(
                            width: barWidth,
                            height: height,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                math.min(8, barWidth / 2),
                              ),
                              gradient: b.ms == 0
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: b.isCurrent
                                          ? [palette.accent, palette.accentDeep]
                                          : [
                                              palette.accent.withValues(
                                                alpha: 0.55,
                                              ),
                                              palette.accent.withValues(
                                                alpha: 0.3,
                                              ),
                                            ],
                                    ),
                              color: b.ms == 0 ? palette.track : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 14,
                      child: Text(
                        _label(b, i),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              b.isCurrent ? FontWeight.w800 : FontWeight.w500,
                          color: b.isCurrent ? palette.text : palette.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---- Listening clock --------------------------------------------------------

class _ClockCard extends StatelessWidget {
  const _ClockCard({required this.summary, required this.palette});

  final ListeningSummary summary;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final peak = summary.peakHour;
    final (type, icon) = _listenerType(peak);
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: palette.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          if (peak != null)
            Text(
              'Most listening around ${_hourLabel(peak)}',
              style: TextStyle(fontSize: 12, color: palette.secondary),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: _ClockPainter(
                    hourly: summary.hourly,
                    accent: palette.accent,
                    track: palette.track,
                    label: palette.secondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 24 spokes round a dial, each as long as that hour's listening.
class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.hourly,
    required this.accent,
    required this.track,
    required this.label,
  });

  final List<int> hourly;
  final Color accent;
  final Color track;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    // A small hub, spokes out to 74 %, and the hour marks outside them.
    final inner = radius * 0.22;
    final outer = radius * 0.74;
    final maxMs = hourly.fold<int>(0, math.max);

    canvas.drawCircle(
      center,
      inner - 4,
      Paint()..color = track,
    );
    for (var h = 0; h < 24; h++) {
      final angle = (h / 24) * 2 * math.pi - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final fraction = maxMs == 0 ? 0.0 : hourly[h] / maxMs;
      final length = (outer - inner) * math.max(0.06, fraction);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.075
        ..color = fraction > 0
            ? Color.lerp(accent.withValues(alpha: 0.35), accent, fraction)!
            : track;
      canvas.drawLine(
        center + direction * inner,
        center + direction * (inner + length),
        paint,
      );
    }
    final style = TextStyle(
      fontSize: math.max(8, radius * 0.095),
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: label,
    );
    for (final (h, text) in [
      (0, '12am'),
      (6, '6am'),
      (12, '12pm'),
      (18, '6pm'),
    ]) {
      final angle = (h / 24) * 2 * math.pi - math.pi / 2;
      final painter = TextPainter(
        text: TextSpan(text: text, style: withAppFont(style)),
        textDirection: TextDirection.ltr,
      )..layout();
      final at =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (radius * 0.88) -
          Offset(painter.width / 2, painter.height / 2);
      painter.paint(canvas, at);
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.hourly != hourly || old.accent != accent;
}

// ---- Streak -----------------------------------------------------------------

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.summary, required this.palette});

  final ListeningSummary summary;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final current = summary.currentStreak;
    final best = summary.longestStreak;
    final onFire = current >= 3;
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 20,
                color: onFire ? const Color(0xFFFF7A2F) : palette.secondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Streak',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$current',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: palette.text,
                  ),
                ),
                TextSpan(
                  text: current == 1 ? ' day' : ' days',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current == 0
                ? 'Listen today to start a new one'
                : current >= best
                ? 'Your longest yet'
                : 'Longest: $best days',
            style: TextStyle(fontSize: 12, color: palette.secondary),
          ),
          const Spacer(),
          // The last seven days, lit where you listened.
          _WeekDots(summary: summary, palette: palette),
        ],
      ),
    );
  }
}

class _WeekDots extends ConsumerWidget {
  const _WeekDots({required this.summary, required this.palette});

  final ListeningSummary summary;
  final _Palette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref
        .watch(listeningStatsProvider)
        .summarize(StatsPeriod.week, limit: 0)
        .buckets;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final b in week)
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: b.ms >= 60000 ? palette.accent : palette.track,
                  border: b.isCurrent
                      ? Border.all(color: palette.text, width: 1.5)
                      : null,
                ),
                child: b.ms >= 60000
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: _onColor(palette.accent),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                _weekdays[b.start.weekday - 1].substring(0, 1),
                style: TextStyle(fontSize: 10, color: palette.secondary),
              ),
            ],
          ),
      ],
    );
  }
}

// ---- Artists ----------------------------------------------------------------

void _openArtist(BuildContext context, ArtistStat artist) {
  final id = artist.artistId;
  if (id == null || id.isEmpty) return;
  ArtistScreen.open(
    context,
    artistId: id,
    name: artist.name,
    thumbnailUrl: artist.imageUrl,
  );
}

class _TopArtistFeature extends StatelessWidget {
  const _TopArtistFeature({
    required this.artist,
    required this.period,
    required this.palette,
  });

  final ArtistStat artist;
  final StatsPeriod period;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final image = artist.imageUrl;
    return GestureDetector(
      onTap: () => _openArtist(context, artist),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    errorWidget: (_, _, _) =>
                        ColoredBox(color: palette.accentDeep),
                  ),
                )
              else
                ColoredBox(color: palette.accentDeep),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: image == null
                            ? ColoredBox(
                                color: palette.accent,
                                child: const Icon(
                                  Icons.person_rounded,
                                  size: 56,
                                  color: Colors.white,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: image,
                                fit: BoxFit.cover,
                                memCacheWidth: 300,
                              ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              period == StatsPeriod.allTime
                                  ? '#1 ARTIST OF ALL TIME'
                                  : '#1 ARTIST',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: _onColor(palette.accent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            artist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 28,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${formatListening(artist.ms)} · ${artist.plays} ${artist.plays == 1 ? 'play' : 'plays'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artists, required this.palette});

  final List<ArtistStat> artists;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Top artists', palette),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final artist = artists[i];
              return GestureDetector(
                onTap: () => _openArtist(context, artist),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipOval(
                            child: SizedBox.square(
                              dimension: 92,
                              child: artist.imageUrl == null
                                  ? ColoredBox(
                                      color: palette.track,
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: palette.secondary,
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: artist.imageUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 240,
                                    ),
                            ),
                          ),
                          Positioned(
                            left: -2,
                            top: -2,
                            child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.accent,
                                border: Border.all(
                                  color: palette.isDark
                                      ? Colors.black
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '${i + 2}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: _onColor(palette.accent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        formatListening(artist.ms),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- Songs ------------------------------------------------------------------

class _TopSongs extends ConsumerWidget {
  const _TopSongs({
    required this.tracks,
    required this.period,
    required this.palette,
    required this.columns,
  });

  final List<TrackStat> tracks;
  final StatsPeriod period;
  final _Palette palette;
  final int columns;

  void _play(WidgetRef ref, int index) {
    ref
        .read(audioPlayerServiceProvider)
        .playQueue(
          [for (final t in tracks) t.track],
          startIndex: index,
          sourceTitle: 'Your top songs',
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final most = tracks.first.plays == 0 ? 1 : tracks.first.plays;
    final rows = [
      for (final (i, stat) in tracks.indexed)
        _SongRow(
          rank: i + 1,
          stat: stat,
          fraction: stat.plays / most,
          palette: palette,
          onTap: () => _play(ref, i),
        ),
    ];
    final perColumn = (rows.length / columns).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Top songs',
          palette,
          trailing: FilledButton.icon(
            onPressed: () => _play(ref, 0),
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: _onColor(palette.accent),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Play all'),
          ),
        ),
        _Card(
          palette: palette,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: columns == 1
              ? Column(children: rows)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        child: Column(
                          children: rows
                              .skip(c * perColumn)
                              .take(perColumn)
                              .toList(),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.rank,
    required this.stat,
    required this.fraction,
    required this.palette,
    required this.onTap,
  });

  final int rank;
  final TrackStat stat;
  final double fraction;
  final _Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = stat.track;
    final art = track.thumbnailUrl ?? track.highResThumbnailUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: rank <= 3 ? 18 : 15,
                  fontWeight: FontWeight.w900,
                  color: rank <= 3 ? palette.accent : palette.secondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 50,
                child: art == null
                    ? ColoredBox(
                        color: palette.track,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: palette.secondary,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: art,
                        fit: BoxFit.cover,
                        memCacheWidth: 150,
                        errorWidget: (_, _, _) => ColoredBox(
                          color: palette.track,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: palette.secondary,
                          ),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: palette.secondary),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.02, 1.0),
                      minHeight: 4,
                      backgroundColor: palette.track,
                      valueColor: AlwaysStoppedAnimation(
                        palette.accent.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Heard but never long enough to count: show the time.
                Text(
                  stat.plays > 0 ? '${stat.plays}' : formatListening(stat.ms),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: palette.text,
                  ),
                ),
                Text(
                  stat.plays == 0
                      ? 'heard'
                      : stat.plays == 1
                      ? 'play'
                      : 'plays',
                  style: TextStyle(fontSize: 11, color: palette.secondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Albums -----------------------------------------------------------------

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.albums, required this.palette});

  final List<AlbumStat> albums;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Top albums', palette),
        SizedBox(
          height: 206,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final album = albums[i];
              final id = album.albumId;
              return GestureDetector(
                onTap: id == null || id.isEmpty
                    ? null
                    : () => AlbumScreen.open(
                        context,
                        albumId: id,
                        title: album.name,
                        artist: album.artist,
                        thumbnailUrl: album.imageUrl,
                      ),
                child: SizedBox(
                  width: 148,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox.square(
                          dimension: 148,
                          child: album.imageUrl == null
                              ? ColoredBox(
                                  color: palette.track,
                                  child: Icon(
                                    Icons.album_rounded,
                                    size: 40,
                                    color: palette.secondary,
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: album.imageUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 300,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        '${album.artist} · ${formatListening(album.ms)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- Insights ---------------------------------------------------------------

class _InsightItem {
  const _InsightItem({
    required this.icon,
    required this.tag,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    this.progress,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String value;
  final String subtitle;
  final Color accentColor;
  final double? progress;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.item,
    required this.palette,
  });

  final _InsightItem item;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final isDark = palette.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.accentColor.withValues(
                    alpha: isDark ? 0.16 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.accentColor.withValues(
                      alpha: isDark ? 0.28 : 0.20,
                    ),
                    width: 1,
                  ),
                ),
                child: Icon(item.icon, size: 19, color: item.accentColor),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7.5,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: item.accentColor.withValues(
                    alpha: isDark ? 0.12 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.tag,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: item.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.secondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: item.progress!.clamp(0.0, 1.0),
                    backgroundColor: palette.track,
                    valueColor: AlwaysStoppedAnimation<Color>(item.accentColor),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: palette.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({
    required this.summary,
    required this.palette,
    required this.wide,
  });

  final ListeningSummary summary;
  final _Palette palette;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final favouriteDay = summary.peakWeekday;
    final busiest = summary.busiestDay;

    final items = <_InsightItem>[
      if (favouriteDay != null)
        _InsightItem(
          icon: Iconsax.calendar_tick,
          tag: 'HABIT',
          title: 'Favourite day',
          value: _weekdays[favouriteDay],
          subtitle: '${formatListening(summary.weekday[favouriteDay])} listened',
          accentColor: const Color(0xFF6366F1),
        ),
      if (busiest != null)
        _InsightItem(
          icon: Iconsax.flash_1,
          tag: 'PEAK',
          title: 'Busiest day',
          value: formatListening(summary.busiestDayMs),
          subtitle: 'On ${_dateLabel(busiest)}',
          accentColor: const Color(0xFFF59E0B),
        ),
      _InsightItem(
        icon: Iconsax.discover_1,
        tag: 'DISCOVERY',
        title: 'New discoveries',
        value: '${summary.newTracks} ${summary.newTracks == 1 ? 'song' : 'songs'}',
        subtitle: switch (summary.period) {
          StatsPeriod.week => 'First heard this week',
          StatsPeriod.month => 'First heard this month',
          StatsPeriod.year => 'First heard this year',
          StatsPeriod.allTime => 'Total tracks discovered',
        },
        accentColor: const Color(0xFF8B5CF6),
      ),
      _InsightItem(
        icon: Iconsax.chart_21,
        tag: 'PACE',
        title: 'Daily average',
        value: formatListening(summary.totalMs ~/ math.max(1, summary.days)),
        subtitle: 'Over ${summary.days} days',
        accentColor: const Color(0xFF06B6D4),
      ),
      _InsightItem(
        icon: Iconsax.trend_up,
        tag: 'CONSISTENCY',
        title: 'Days listened',
        value: '${summary.activeDays} of ${summary.days} days',
        subtitle:
            '${((summary.activeDays / math.max(1, summary.days)) * 100).round()}% active rate',
        progress: summary.activeDays / math.max(1, summary.days),
        accentColor: const Color(0xFF10B981),
      ),
      if (summary.plays > 0)
        _InsightItem(
          icon: Iconsax.music_play,
          tag: 'AVERAGE',
          title: 'Per play',
          value: formatListening(summary.totalMs ~/ summary.plays),
          subtitle: 'From ${summary.plays} plays',
          accentColor: const Color(0xFFEC4899),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Insights', palette),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 360 ? 1 : (wide ? 3 : 2);
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 154),
                      child: _InsightCard(item: item, palette: palette),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---- Empty ------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.wholeLibrary});

  final _Palette palette;
  final bool wholeLibrary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [palette.accent, palette.accentDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Iconsax.music_dashboard,
              size: 52,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            wholeLibrary ? 'Your stats start here' : 'Nothing here yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wholeLibrary
                ? 'Play some music and this fills up with your listening time, '
                      'top artists, top songs and when you listen most.'
                : 'Nothing was played in this period. Try a longer one.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: palette.secondary),
          ),
        ],
      ),
    );
  }
}
