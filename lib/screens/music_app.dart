import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design_system/design_system.dart';
import '../providers/providers.dart';
import 'tabs/home_tab.dart';
import 'tabs/songs_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/folders_tab.dart';
import 'widgets/mini_player.dart';
import 'widgets/now_playing_screen.dart';

/// Standalone Music App with its own navigation
class MusicApp extends ConsumerStatefulWidget {
  const MusicApp({super.key});

  @override
  ConsumerState<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends ConsumerState<MusicApp>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animationController;

  final List<Widget> _tabs = const [
    MusicHomeTab(),
    MusicSongsTab(),
    MusicLibraryTab(),
    MusicFoldersTab(),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      _animationController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playbackState = ref.watch(playbackStateProvider);
    final hasCurrentTrack =
        playbackState.whenOrNull(data: (s) => s.currentTrack != null) ?? false;

    // Dynamic background color based on album art
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;

    // Background with subtle tint when no album colors
    final backgroundColor = hasAlbumColors
        ? albumColors.backgroundSecondary
        : (isDark ? MineColors.darkBackground : MineColors.background);

    // Accent color for nav items
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_currentIndex != 0) {
            setState(() => _currentIndex = 0);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            // Strong accent gradient at the very top (like YT Music)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 250,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: hasAlbumColors
                        ? [
                            albumColors.accent.withValues(
                              alpha: isDark ? 0.4 : 0.25,
                            ),
                            albumColors.accent.withValues(alpha: 0),
                          ]
                        : [
                            accentColor.withValues(alpha: isDark ? 0.35 : 0.2),
                            accentColor.withValues(alpha: 0),
                          ],
                  ),
                ),
              ),
            ),
            // Main content
            Column(
              children: [
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: _tabs),
                ),
                // Space for mini player + nav (combined at bottom)
                SizedBox(
                  height:
                      (hasCurrentTrack
                          ? 60
                          : 0) + // Mini player height (reduced to prevent gap)
                      85 +
                      MediaQuery.of(context).padding.bottom,
                ),
              ],
            ),
            // Mini player + nav bar positioned at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasCurrentTrack)
                    MusicMiniPlayer(
                      onTap: () => NowPlayingScreen.show(context),
                    ),
                  _ModernFloatingNav(
                    currentIndex: _currentIndex,
                    onTap: _onTabSelected,
                    isDark: isDark,
                    accentColor: accentColor,
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

/// Modern floating glassmorphic bottom navigation
class _ModernFloatingNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isDark;
  final Color accentColor;

  const _ModernFloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<_ModernFloatingNav> createState() => _ModernFloatingNavState();
}

class _ModernFloatingNavState extends State<_ModernFloatingNav>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late Animation<double> _slideAnimation;
  late Animation<double> _bounceAnimation;
  int _previousIndex = 0;

  static const _navItems = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.music_note_outlined, Icons.music_note_rounded, 'Songs'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Folders'),
  ];

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation =
        Tween<double>(
          begin: widget.currentIndex.toDouble(),
          end: widget.currentIndex.toDouble(),
        ).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );

    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ModernFloatingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _slideAnimation =
          Tween<double>(
            begin: _previousIndex.toDouble(),
            end: widget.currentIndex.toDouble(),
          ).animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutBack,
            ),
          );
      _slideController.forward(from: 0);

      // Bounce animation for selected item
      _bounceAnimation =
          TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 20),
            TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 40),
            TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 40),
          ]).animate(
            CurvedAnimation(parent: _bounceController, curve: Curves.easeOut),
          );
      _bounceController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 85 + bottomPadding,
          padding: EdgeInsets.only(bottom: bottomPadding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.05),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.85),
                      Colors.white.withValues(alpha: 0.65),
                    ],
            ),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.8),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, -5),
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.3 : 0.08,
                ),
                blurRadius: 20,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / 4;
              final indicatorWidth = 48.0;

              return Stack(
                alignment: Alignment.center,
                children: [
                  // Animated glow indicator
                  AnimatedBuilder(
                    animation: _slideController,
                    builder: (context, child) {
                      final position = _slideController.isAnimating
                          ? _slideAnimation.value
                          : widget.currentIndex.toDouble();
                      final leftOffset =
                          (itemWidth - indicatorWidth) / 2 +
                          (position * itemWidth);

                      return Positioned(
                        left: leftOffset,
                        top: 8,
                        child: Container(
                          width: indicatorWidth,
                          height: indicatorWidth,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                widget.accentColor.withValues(alpha: 0.4),
                                widget.accentColor.withValues(alpha: 0.1),
                                widget.accentColor.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.accentColor.withValues(
                                  alpha: 0.5,
                                ),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Nav items
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_navItems.length, (index) {
                      final item = _navItems[index];
                      final isSelected = widget.currentIndex == index;

                      return GestureDetector(
                        onTap: () => widget.onTap(index),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: itemWidth,
                          child: AnimatedBuilder(
                            animation: _bounceController,
                            builder: (context, child) {
                              final scale =
                                  isSelected && _bounceController.isAnimating
                                  ? _bounceAnimation.value
                                  : 1.0;
                              return Transform.scale(
                                scale: scale,
                                child: _NavItemWidget(
                                  icon: item.$1,
                                  selectedIcon: item.$2,
                                  label: item.$3,
                                  isSelected: isSelected,
                                  accentColor: widget.accentColor,
                                  isDark: widget.isDark,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItemWidget extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;

  const _NavItemWidget({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon with animated properties
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(
            isSelected ? selectedIcon : icon,
            size: isSelected ? 26 : 24,
            color: isSelected
                ? accentColor
                : (isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ),
        // Label
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: isSelected ? 11 : 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? accentColor
                : (isDark ? Colors.white60 : Colors.grey.shade600),
            letterSpacing: isSelected ? 0.3 : 0,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}

/// Custom curve for smooth spring effect
class _LiquidGlassCurve extends Curve {
  const _LiquidGlassCurve();

  @override
  double transformInternal(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final result = 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
    return result.clamp(0.0, 1.2);
  }
}
