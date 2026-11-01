import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/design_system/design_system.dart';
import '../../services/automix/automix_service.dart';

/// Audio settings → Automix, as BitChord lays it out: the switch, and the
/// analysis performance picker. (The crossfade slider above hides while
/// Automix is on — it decides each transition's length itself.)
class AutomixSettingsCard extends StatelessWidget {
  const AutomixSettingsCard({
    super.key,
    required this.isDark,
    required this.accentColor,
    required this.switchBuilder,
  });

  final bool isDark;
  final Color accentColor;
  final Widget Function(bool value, ValueChanged<bool>? onChanged)
  switchBuilder;

  Color get _primary => isDark ? Colors.white : InzxColors.textPrimary;
  Color get _secondary => isDark ? Colors.white54 : InzxColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final automix = AutomixService.instance;
    return ListenableBuilder(
      listenable: automix,
      builder: (context, _) {
        final on = automix.enabled;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white12 : accentColor.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _icon(Iconsax.music_filter, on),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Automix [BETA]',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          on
                              ? 'Times and blends every transition from the '
                                    'tracks themselves. Turn it off if the phone '
                                    'gets hot or playback stutters.'
                              : 'Times and blends transitions automatically, '
                                    'without a slider. Performance may vary on '
                                    'slower devices.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _secondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  switchBuilder(on, (v) {
                    HapticFeedback.selectionClick();
                    automix.setEnabled(v);
                  }),
                ],
              ),
              Divider(
                height: 24,
                color: isDark ? Colors.white10 : Colors.grey.shade300,
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pickPerformance(context, automix),
                child: Row(
                  children: [
                    _icon(Iconsax.cpu, false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Automix performance',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sets how much CPU background analysis may use',
                            style: TextStyle(fontSize: 13, color: _secondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      automix.mode.label,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: _secondary),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _icon(IconData icon, bool active) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: active
          ? accentColor.withValues(alpha: 0.2)
          : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 22, color: active ? accentColor : _secondary),
  );

  static String _modeSubtitle(AutomixService automix, AutomixPerformanceMode m) {
    final n = automix.threadsFor(m);
    final threads = '$n thread${n == 1 ? '' : 's'}';
    return switch (m) {
      AutomixPerformanceMode.efficient =>
        '$threads · lowest heat and battery use · analysis may take longer',
      AutomixPerformanceMode.balanced =>
        '$threads · recommended balance of speed, heat and battery',
      AutomixPerformanceMode.performance =>
        '$threads · fastest analysis · higher heat and battery use',
    };
  }

  void _pickPerformance(BuildContext context, AutomixService automix) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: ListenableBuilder(
            listenable: automix,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automix performance',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 10),
                RadioGroup<AutomixPerformanceMode>(
                  groupValue: automix.mode,
                  onChanged: (v) {
                    if (v != null) automix.setMode(v);
                  },
                  child: Column(
                    children: [
                      for (final m in AutomixPerformanceMode.values)
                        RadioListTile<AutomixPerformanceMode>(
                          contentPadding: EdgeInsets.zero,
                          value: m,
                          activeColor: accentColor,
                          title: Text(m.label, style: TextStyle(color: _primary)),
                          subtitle: Text(
                            _modeSubtitle(automix, m),
                            style: TextStyle(fontSize: 12.5, color: _secondary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${automix.fastCores != null ? 'Sized for this phone: '
                            '${automix.fastCores} fast cores of '
                            '${automix.cores}. ' : ''}'
                  'Higher performance analyses tracks faster, but can use more '
                  'battery and make the phone warmer.',
                  style: TextStyle(fontSize: 12.5, color: _secondary, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
