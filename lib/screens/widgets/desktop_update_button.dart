import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design_system/design_system.dart';
import '../../main.dart' show rootNavigatorKey;
import '../../providers/providers.dart';
import '../../services/desktop/desktop_updater.dart';

/// The top bar's update indicator, beside Jams: hidden until a newer
/// release exists, a ring while it downloads, a dot once it's ready. Tapping
/// it explains what will happen and offers to update now.
class DesktopUpdateButton extends ConsumerWidget {
  const DesktopUpdateButton({super.key, required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(effectiveAccentColorProvider);
    final updater = DesktopUpdater.instance;
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final update = updater.update;
        final phase = updater.phase;
        if (update == null ||
            phase == DesktopUpdatePhase.idle ||
            phase == DesktopUpdatePhase.checking) {
          return const SizedBox.shrink();
        }
        final String tooltip;
        Widget icon = Icon(Icons.system_update_alt_rounded, size: 20, color: accent);
        switch (phase) {
          case DesktopUpdatePhase.downloading:
            final pct = ((updater.progress ?? 0) * 100).round();
            tooltip = 'Downloading Inzx ${update.version} · $pct%';
            icon = SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: updater.progress,
                    strokeWidth: 2,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.18),
                  ),
                  Icon(Icons.arrow_downward_rounded, size: 13, color: accent),
                ],
              ),
            );
          case DesktopUpdatePhase.ready:
            tooltip = updater.autoUpdate
                ? 'Inzx ${update.version} installs when you close Inzx'
                : 'Inzx ${update.version} is ready to install';
            icon = Badge(
              smallSize: 8,
              backgroundColor: accent,
              offset: const Offset(2, -2),
              child: icon,
            );
          case DesktopUpdatePhase.failed:
            tooltip = "Inzx ${update.version}: the update couldn't download";
          default:
            tooltip = 'Inzx ${update.version} is available';
            icon = Badge(
              smallSize: 8,
              backgroundColor: accent,
              offset: const Offset(2, -2),
              child: icon,
            );
        }
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: IconButton(
            tooltip: tooltip,
            style: IconButton.styleFrom(backgroundColor: accent.withValues(alpha: 0.14)),
            onPressed: () => showDetails(context),
            icon: icon,
          ),
        );
      },
    );
  }

  /// The update's details and what can be done with it now.
  static Future<void> showDetails(BuildContext context) {
    // The top bar sits above the app's navigator; dialogs go on that one.
    final navContext = rootNavigatorKey.currentContext ?? context;
    return showDialog<void>(
      context: navContext,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) => _UpdateDialog(accent: ref.watch(effectiveAccentColorProvider)),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? Colors.white60 : InzxColors.textSecondary;
    final updater = DesktopUpdater.instance;
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final update = updater.update;
        if (update == null) return const SizedBox.shrink();
        final phase = updater.phase;
        final canInstall = DesktopUpdater.canSelfUpdate;

        final String status;
        switch (phase) {
          case DesktopUpdatePhase.ready:
            status = updater.autoUpdate
                ? "Downloaded. It installs when you close Inzx, or now if you'd rather."
                : 'Downloaded and ready to install.';
          case DesktopUpdatePhase.downloading:
            status = 'Downloading in the background '
                '(${((updater.progress ?? 0) * 100).round()}%). You can keep listening.';
          case DesktopUpdatePhase.failed:
            status = "The download didn't finish (${updater.error ?? 'unknown error'}).";
          default:
            status = canInstall
                ? 'Inzx can download and install it for you.'
                : "This copy of Inzx wasn't installed with the installer, so it "
                      "can't update itself. Get the new version from the release page.";
        }

        final notes = update.notes;
        return AlertDialog(
          title: Text('Inzx ${update.version}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: TextStyle(color: secondary, height: 1.35)),
                if (phase == DesktopUpdatePhase.downloading) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: updater.progress, color: accent),
                ],
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text("What's new", style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Text(notes, style: TextStyle(color: secondary, height: 1.4)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(phase == DesktopUpdatePhase.downloading ? 'Hide' : 'Later'),
            ),
            if (!canInstall || phase == DesktopUpdatePhase.failed)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(update.releaseUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Release page'),
              ),
            if (canInstall && phase == DesktopUpdatePhase.ready)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: updater.installNow,
                child: const Text('Restart and update'),
              ),
            if (canInstall &&
                (phase == DesktopUpdatePhase.available || phase == DesktopUpdatePhase.failed))
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: updater.download,
                child: Text(phase == DesktopUpdatePhase.failed ? 'Try again' : 'Download'),
              ),
          ],
        );
      },
    );
  }
}
