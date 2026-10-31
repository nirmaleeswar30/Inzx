import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_system/colors.dart';
import '../../providers/providers.dart';
import '../audio_settings_screen.dart';

/// Heads-up shown on app open while the JioSaavn high-quality source is on:
/// its catalogue is matched by title/artist, so it can occasionally pick the
/// wrong song. Shown until the user taps "Don't show again".
class JioSaavnNoticeSheet extends ConsumerWidget {
  const JioSaavnNoticeSheet({super.key});

  static const String dismissedPrefKey = 'inzx_jiosaavn_notice_dismissed';
  static bool _shownThisLaunch = false;

  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    if (_shownThisLaunch) return;
    if (!ref.read(jioSaavnEnabledProvider)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(dismissedPrefKey) ?? false) return;
    if (!context.mounted) return;
    _shownThisLaunch = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const JioSaavnNoticeSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(effectiveAccentColorProvider);
    final textPrimary = isDark ? Colors.white : InzxColors.textPrimary;
    final textSecondary = isDark ? Colors.white70 : InzxColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/icon/JioSaavn.png',
                  width: 64,
                  height: 64,
                  cacheWidth: 192,
                ),
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Iconsax.warning_2,
                    size: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Heads up about JioSaavn',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'High quality (320 kbps) streams come from JioSaavn and are matched '
            'by song title and artist. Once in a while it may load a different '
            'song or version. If that happens, you can turn it off in '
            'Settings → Audio.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: InzxColors.contrastTextOn(accent),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    await navigator.push(
                      MaterialPageRoute(
                        builder: (_) => const AudioSettingsScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Audio settings',
                    style: TextStyle(color: textSecondary),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(dismissedPrefKey, true);
                    navigator.pop();
                  },
                  child: Text(
                    "Don't show again",
                    style: TextStyle(color: textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
