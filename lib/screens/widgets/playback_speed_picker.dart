import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

/// Playback speed picker bottom sheet
class PlaybackSpeedPicker extends ConsumerWidget {
  const PlaybackSpeedPicker({super.key});

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const PlaybackSpeedPicker(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.watch(audioPlayerServiceProvider);
    final currentSpeed = ref.watch(playbackSpeedProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white30 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Playback Speed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),

          const Divider(height: 1),

          // Speed options
          ...speeds.map(
            (speed) => _buildSpeedOption(
              context,
              speed: speed,
              isSelected: (currentSpeed - speed).abs() < 0.01,
              isDark: isDark,
              colorScheme: colorScheme,
              onTap: () {
                playerService.setSpeed(speed);
                Navigator.pop(context);
              },
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSpeedOption(
    BuildContext context, {
    required double speed,
    required bool isSelected,
    required bool isDark,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    final label = speed == 1.0 ? 'Normal' : '${speed}x';

    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.circle_outlined,
        color: isSelected
            ? colorScheme.primary
            : (isDark ? Colors.white38 : Colors.grey),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: speed == 1.0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Default',
                style: TextStyle(fontSize: 11, color: colorScheme.primary),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Compact speed button for player controls
class PlaybackSpeedButton extends ConsumerWidget {
  final double size;

  const PlaybackSpeedButton({super.key, this.size = 24});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => PlaybackSpeedPicker.show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: speed != 1.0
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
        ),
        child: Text(
          speed == 1.0 ? '1x' : '${speed}x',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: speed != 1.0
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}
