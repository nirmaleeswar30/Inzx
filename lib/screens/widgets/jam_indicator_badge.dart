import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import 'jams_panel.dart';

/// Animated live Jam session indicator badge for Now Playing screens.
///
/// Automatically hides when not in an active Jam session. Tapping the badge
/// opens the Jams panel bottom sheet.
class JamIndicatorBadge extends ConsumerStatefulWidget {
  final Color? textColor;
  final Color? accentColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const JamIndicatorBadge({
    super.key,
    this.textColor,
    this.accentColor,
    this.backgroundColor,
    this.onTap,
  });

  @override
  ConsumerState<JamIndicatorBadge> createState() => _JamIndicatorBadgeState();
}

class _JamIndicatorBadgeState extends ConsumerState<JamIndicatorBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInJam = ref.watch(isInJamSessionProvider);
    if (!isInJam) return const SizedBox.shrink();

    final session = ref.watch(currentJamSessionProvider).valueOrNull;
    final participantCount = session?.participantCount ?? session?.participants.length ?? 0;

    final theme = Theme.of(context);
    final albumColors = ref.watch(albumColorsProvider);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveAccent = widget.accentColor ??
        (!albumColors.isDefault
            ? albumColors.accent
            : theme.colorScheme.primary);

    final effectiveText = widget.textColor ??
        (!albumColors.isDefault
            ? albumColors.onBackground
            : theme.colorScheme.onSurface);

    // Badge pill background (semi-transparent frosted glass)
    final effectiveBadgeBg = (widget.backgroundColor != null && widget.backgroundColor!.a < 1.0)
        ? widget.backgroundColor!
        : effectiveAccent.withValues(alpha: 0.16);

    // Sheet background (always solid/opaque for JamsPanel)
    final effectiveSheetBg = (widget.backgroundColor != null && widget.backgroundColor!.a == 1.0)
        ? widget.backgroundColor!
        : (!albumColors.isDefault
            ? albumColors.backgroundPrimary
            : (isDark ? const Color(0xFF141414) : Colors.white)).withValues(alpha: 1.0);

    return BouncyTouch(
      style: BouncyStyle.button,
      customScale: 0.92,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onTap != null) {
          widget.onTap!();
        } else {
          JamsPanel.show(
            context,
            backgroundColor: effectiveSheetBg,
            textColor: (!albumColors.isDefault
                ? albumColors.onBackground
                : theme.colorScheme.onSurface),
            accentColor: effectiveAccent,
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: effectiveBadgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: effectiveAccent.withValues(alpha: 0.38),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: effectiveAccent.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: -1,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing live indicator dot
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final scale = 0.8 + (_pulseAnimation.value * 0.4);
                    final glowOpacity = 0.3 + (_pulseAnimation.value * 0.7);
                    return Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: effectiveAccent,
                        boxShadow: [
                          BoxShadow(
                            color: effectiveAccent.withValues(alpha: glowOpacity),
                            blurRadius: 6 * scale,
                            spreadRadius: 1.5 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                // "JAM" label
                Text(
                  'JAM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: effectiveText,
                  ),
                ),
                if (participantCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: effectiveText.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Iconsax.profile_2user,
                    size: 11.5,
                    color: effectiveText.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$participantCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: effectiveText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
