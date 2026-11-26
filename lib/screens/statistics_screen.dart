import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../core/design_system/design_system.dart';
import '../core/l10n/app_localizations_x.dart';
import '../core/utils/platform_utils.dart';
import '../services/listening_stats_service.dart';
import 'widgets/listening_stats_view.dart';

/// Your listening: time, activity, top artists, songs and albums for the
/// week, month, year or all time.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StatisticsScreen()),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final l10n = context.l10n;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearStatistics),
        content: const Text(
          'This removes your listening time, play counts, top artists and '
          'songs, and your streak. It can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    await ListeningStatsService.instance.clear();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.statisticsCleared)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: desktopPageBackground(
        isDark ? InzxColors.darkBackground : InzxColors.background,
      ),
      appBar: AppBar(
        title: const Text(
          'Your listening',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<void>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => _confirmClear(context),
                child: Row(
                  children: [
                    const Icon(Iconsax.trash, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.clearStatistics),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: const ListeningStatsView(),
    );
  }
}
