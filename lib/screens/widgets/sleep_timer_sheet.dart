import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/design_system.dart';
import '../../services/sleep_timer_service.dart';

/// Pick how long until the music stops (5 minutes to 12 hours), or see and
/// change a timer that's already running.
class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({super.key, required this.accentColor});

  final Color accentColor;

  static Future<void> show(BuildContext context, {required Color accentColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SleepTimerSheet(accentColor: accentColor),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  static const _presets = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(hours: 1),
    Duration(hours: 2),
  ];

  // Index into SleepTimerService.steps; starts on 30 min.
  int _step = SleepTimerService.steps.indexOf(const Duration(minutes: 30));

  void _start(Duration d) {
    HapticFeedback.selectionClick();
    SleepTimerService.instance.start(d);
    Navigator.pop(context);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Music will stop in ${SleepTimerService.format(d)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark ? Colors.white54 : InzxColors.textSecondary;
    final accent = widget.accentColor;
    final service = SleepTimerService.instance;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final remaining = service.remaining;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sleep timer',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The music fades out and pauses when it runs out.',
                  style: TextStyle(fontSize: 13.5, color: secondary),
                ),
                const SizedBox(height: 18),
                if (remaining != null)
                  _running(remaining, primary, secondary, accent, isDark)
                else
                  _picker(primary, secondary, accent, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _running(
    Duration remaining,
    Color primary,
    Color secondary,
    Color accent,
    bool isDark,
  ) {
    final service = SleepTimerService.instance;
    final total = service.total ?? remaining;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : remaining.inMilliseconds / total.inMilliseconds;
    final canExtend = remaining + const Duration(minutes: 10) <=
        SleepTimerService.maximum;
    return Column(
      children: [
        Center(
          child: SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.15),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SleepTimerService.format(remaining, precise: true),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text('left', style: TextStyle(color: secondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canExtend
                    ? () => service.extend(const Duration(minutes: 10))
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('+10 min'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  service.cancel();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: _readableOn(accent),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Turn off'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _picker(Color primary, Color secondary, Color accent, bool isDark) {
    final steps = SleepTimerService.steps;
    final chosen = steps[_step];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _presets)
              ActionChip(
                label: Text(SleepTimerService.format(d)),
                onPressed: () => _start(d),
                labelStyle: TextStyle(color: primary, fontWeight: FontWeight.w500),
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              'Custom',
              style: TextStyle(fontWeight: FontWeight.w600, color: primary),
            ),
            const Spacer(),
            Text(
              SleepTimerService.format(chosen),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withValues(alpha: 0.15),
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.12),
            trackHeight: 6,
          ),
          child: Slider(
            value: _step.toDouble(),
            min: 0,
            max: (steps.length - 1).toDouble(),
            divisions: steps.length - 1,
            onChanged: (v) {
              final i = v.round();
              if (i != _step) {
                HapticFeedback.selectionClick();
                setState(() => _step = i);
              }
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('5 min', style: TextStyle(fontSize: 12, color: secondary)),
            Text('12 h', style: TextStyle(fontSize: 12, color: secondary)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () => _start(chosen),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: _readableOn(accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Start · ${SleepTimerService.format(chosen)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// Black or white, whichever reads on [color] (the accent can be black).
Color _readableOn(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
