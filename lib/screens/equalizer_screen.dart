import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../services/equalizer_service.dart';

/// Seven-band equaliser with presets. Changes are heard immediately (the
/// native processor glides to them), on both crossfade players.
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  final _eq = EqualizerService.instance;

  @override
  void initState() {
    super.initState();
    _eq.load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);
    final accent = albumColors.isDefault
        ? Theme.of(context).colorScheme.primary
        : albumColors.accent;
    final background = (!albumColors.isDefault && isDark)
        ? albumColors.backgroundSecondary
        : (isDark ? InzxColors.darkBackground : InzxColors.background);
    final primary = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark ? Colors.white54 : InzxColors.textSecondary;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Equalizer'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ListenableBuilder(
            listenable: _eq,
            builder: (context, _) => Switch(
              value: _eq.enabled,
              onChanged: _eq.setEnabled,
              activeThumbColor: Colors.white,
              activeTrackColor: accent,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _eq,
        builder: (context, _) {
          final on = _eq.enabled;
          final current = _eq.preset;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                on
                    ? 'Preset: ${current.label}'
                    : 'Off — music plays untouched',
                style: TextStyle(color: secondary, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: on ? 1 : 0.45,
                child: _bands(accent, primary, secondary, isDark, on),
              ),
              const SizedBox(height: 26),
              Text(
                'PRESETS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in EqualizerPreset.values)
                    if (p != EqualizerPreset.custom)
                      _presetChip(p, on && p == current, accent, primary, isDark),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Turned off automatically while bit-perfect USB output is on, '
                'since any EQ changes the samples.',
                style: TextStyle(fontSize: 12.5, color: secondary, height: 1.35),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bands(
    Color accent,
    Color primary,
    Color secondary,
    bool isDark,
    bool on,
  ) {
    final gains = _eq.gains;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (var i = 0; i < EqualizerService.bandsHz.length; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${gains[i] > 0 ? '+' : ''}${gains[i].toStringAsFixed(gains[i] % 1 == 0 ? 0 : 1)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: accent,
                          inactiveTrackColor: accent.withValues(alpha: 0.18),
                          thumbColor: accent,
                          overlayColor: accent.withValues(alpha: 0.12),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: gains[i],
                          min: -EqualizerService.maxDb,
                          max: EqualizerService.maxDb,
                          divisions: (EqualizerService.maxDb * 4).toInt(),
                          onChanged: on
                              ? (v) {
                                  if ((v - gains[i]).abs() >= 0.5) {
                                    HapticFeedback.selectionClick();
                                  }
                                  _eq.setBand(i, v);
                                }
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    EqualizerService.bandLabel(EqualizerService.bandsHz[i]),
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _presetChip(
    EqualizerPreset p,
    bool selected,
    Color accent,
    Color primary,
    bool isDark,
  ) {
    return ChoiceChip(
      label: Text(p.label),
      selected: selected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        _eq.applyPreset(p);
      },
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? _readableOn(accent) : primary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: accent,
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
      side: BorderSide(
        color: selected
            ? accent
            : (isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

Color _readableOn(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
