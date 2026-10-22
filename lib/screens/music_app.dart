import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../models/models.dart';
import '../../../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../providers/bookmarks_and_stats_provider.dart';
import '../../core/providers/theme_provider.dart';
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
  String? _lastTrackedId;
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
    // Keep stats and recent history in sync with real playback transitions.
    ref.listen<Track?>(currentTrackProvider, (previous, next) {
      if (next == null) return;
      if (_lastTrackedId == next.id) return;
      _lastTrackedId = next.id;

      ref.read(recentlyPlayedProvider.notifier).addTrack(next);
      ref.read(playStatisticsProvider.notifier).recordPlay(next);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playbackState = ref.watch(playbackStateProvider);
    final hasCurrentTrack =
        playbackState.whenOrNull(data: (s) => s.currentTrack != null) ?? false;

    // Dynamic background color based on album art
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;

    // Background: In dark mode use album colors, in light mode use plain white
    final Color backgroundColor;
    if (hasAlbumColors && isDark) {
      backgroundColor = albumColors.backgroundSecondary;
    } else {
      backgroundColor = isDark
          ? InzxColors.darkBackground
          : InzxColors.background;
    }

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
        resizeToAvoidBottomInset: false,
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
            // Main content (extends full screen behind floating nav)
            Positioned.fill(
              child: IndexedStack(index: _currentIndex, children: _tabs),
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

/// Modern floating bottom navigation that dynamically switches between
/// the standard navbar (from commit 6ee4ad9) and the Liquid Glass navbar
/// based on the user's preference in Settings.
class _ModernFloatingNav extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiquidGlass = ref.watch(liquidGlassNavProvider);
    if (isLiquidGlass) {
      return _LiquidGlassFloatingNav(
        currentIndex: currentIndex,
        onTap: onTap,
        isDark: isDark,
        accentColor: accentColor,
      );
    }
    return _StandardFloatingNav(
      currentIndex: currentIndex,
      onTap: onTap,
      isDark: isDark,
      accentColor: accentColor,
    );
  }
}

/// Standard floating bottom navigation (from commit 6ee4ad9).
/// Default navigation bar when Liquid Glass is not enabled.
class _StandardFloatingNav extends ConsumerStatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isDark;
  final Color accentColor;

  const _StandardFloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.accentColor,
  });

  @override
  ConsumerState<_StandardFloatingNav> createState() =>
      _StandardFloatingNavState();
}

class _StandardFloatingNavState extends ConsumerState<_StandardFloatingNav>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late Animation<double> _slideAnimation;
  late Animation<double> _bounceAnimation;
  int _previousIndex = 0;

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

    _slideAnimation = Tween<double>(
      begin: widget.currentIndex.toDouble(),
      end: widget.currentIndex.toDouble(),
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );

    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 40),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _StandardFloatingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _slideAnimation = Tween<double>(
        begin: _previousIndex.toDouble(),
        end: widget.currentIndex.toDouble(),
      ).animate(
        CurvedAnimation(
          parent: _slideController,
          curve: Curves.easeOutBack,
        ),
      );
      _slideController.forward(from: 0);

      _bounceAnimation = TweenSequence<double>([
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
    final l10n = context.l10n;
    final navItems = [
      (Icons.home_outlined, Icons.home_rounded, l10n.home),
      (Icons.music_note_outlined, Icons.music_note_rounded, l10n.songs),
      (Icons.library_music_outlined, Icons.library_music_rounded, l10n.library),
      (Icons.folder_outlined, Icons.folder_rounded, l10n.folders),
    ];

    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final dynamicAccentColor =
        hasAlbumColors ? albumColors.accent : widget.accentColor;

    final List<Color> gradientColors;
    final Color borderColor = dynamicAccentColor.withValues(
      alpha: widget.isDark ? 0.38 : 0.30,
    );

    if (widget.isDark) {
      gradientColors = [
        Colors.black.withValues(alpha: 0.62),
        const Color(0xFF101010).withValues(alpha: 0.56),
      ];
    } else {
      // Keep the glass a solid dark tint in light mode so the nav labels/icons
      // stay readable instead of washing out over the light page behind it.
      gradientColors = [
        const Color(0xFF1F1F1F).withValues(alpha: 0.94),
        const Color(0xFF121212).withValues(alpha: 0.92),
      ];
    }

    final bottomMargin = (bottomPadding > 0 ? bottomPadding : 10.0) + 14.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomMargin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.isDark ? 0.30 : 0.08,
              ),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
            if (hasAlbumColors)
              BoxShadow(
                color: dynamicAccentColor.withValues(
                  alpha: widget.isDark ? 0.20 : 0.10,
                ),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: borderColor,
                  width: 1.0,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / 4;
                  const indicatorWidth = 44.0;

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
                            top: (56.0 - indicatorWidth) / 2,
                            child: Container(
                              width: indicatorWidth,
                              height: indicatorWidth,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    dynamicAccentColor.withValues(alpha: 0.35),
                                    dynamicAccentColor.withValues(alpha: 0.10),
                                    dynamicAccentColor.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: dynamicAccentColor.withValues(
                                      alpha: 0.40,
                                    ),
                                    blurRadius: 16,
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
                        children: List.generate(navItems.length, (index) {
                          final item = navItems[index];
                          final isSelected = widget.currentIndex == index;

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(index);
                            },
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
                                    child: _StandardNavItemWidget(
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
        ),
      ),
    );
  }
}

class _StandardNavItemWidget extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;

  const _StandardNavItemWidget({
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(
            isSelected ? selectedIcon : icon,
            size: isSelected ? 23 : 21,
            color: isSelected
                ? accentColor
                : Colors.white70,
          ),
        ),
        const SizedBox(height: 1),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: isSelected ? 10.5 : 9.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? accentColor
                : Colors.white70,
            letterSpacing: isSelected ? 0.2 : 0,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}

/// Liquid Glass floating bottom navigation with authentic optical refraction,
/// 72px height, and fluid shape-shifting droplet indicator.
class _LiquidGlassFloatingNav extends ConsumerStatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isDark;
  final Color accentColor;

  const _LiquidGlassFloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.accentColor,
  });

  @override
  ConsumerState<_LiquidGlassFloatingNav> createState() =>
      _LiquidGlassFloatingNavState();
}

class _LiquidGlassFloatingNavState extends ConsumerState<_LiquidGlassFloatingNav>
    with TickerProviderStateMixin {
  late AnimationController _fluidController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;

    // Fluid droplet transit controller
    _fluidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    // Bounce animation for selected tab icon
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.14), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0), weight: 35),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _fluidController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LiquidGlassFloatingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _fluidController.forward(from: 0.0);
      _bounceController.forward(from: 0.0);
    }
  }

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();
    if (index == widget.currentIndex) {
      _bounceController.forward(from: 0.0);
    } else {
      widget.onTap(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final l10n = context.l10n;
    final navItems = [
      (Icons.home_outlined, Icons.home_rounded, l10n.home),
      (Icons.music_note_outlined, Icons.music_note_rounded, l10n.songs),
      (Icons.library_music_outlined, Icons.library_music_rounded, l10n.library),
      (Icons.folder_outlined, Icons.folder_rounded, l10n.folders),
    ];

    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final dynamicAccentColor =
        hasAlbumColors ? albumColors.accent : widget.accentColor;

    final bottomMargin = (bottomPadding > 0 ? bottomPadding : 10.0) + 14.0;
    final navY = MediaQuery.of(context).size.height - bottomMargin - 72.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomMargin),
      child: LiquidGlassContainer(
        borderRadius: 36.0,
        blurSigma: 2.0, // Crisp 2.0px optical liquid dispersion (never frosted fog)
        refractionScale: 1.05, // 5% convex lens optical magnification
        refractionDeflection: 2.8, // Enhanced optical ray bending: visible lateral bend towards center and back
        isDark: widget.isDark,
        surfaceColor: Colors.black.withValues(alpha: widget.isDark ? 0.45 : 0.35),
        accentColor: dynamicAccentColor,
        height: 72.0,
        globalOffset: Offset(10.0, navY),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            if (totalWidth <= 0) return const SizedBox.shrink();
            final contentHeight =
                constraints.maxHeight > 0 ? constraints.maxHeight : 62.0;
            final itemWidth = totalWidth / navItems.length;
            final baseWidth = (itemWidth * 0.82).clamp(52.0, 74.0);
            const baseHeight = 52.0;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Fluid Shape-Shifting Liquid Droplet Indicator
                AnimatedBuilder(
                  animation: _fluidController,
                  builder: (context, child) {
                    final t = _fluidController.value;
                    final double currentCenterX;
                    final double currentWidth;
                    final double stretchRatio;
                    final double currentHeight;

                    if (_previousIndex == widget.currentIndex ||
                        !_fluidController.isAnimating) {
                      currentCenterX = (widget.currentIndex + 0.5) * itemWidth;
                      currentWidth = baseWidth;
                      stretchRatio = 0.0;
                      currentHeight = baseHeight;
                    } else {
                      final startCenterX =
                          (_previousIndex + 0.5) * itemWidth;
                      final endCenterX =
                          (widget.currentIndex + 0.5) * itemWidth;

                      if (widget.currentIndex > _previousIndex) {
                        // Moving right: right edge is leading, left edge is trailing
                        final startLeading = startCenterX + baseWidth / 2;
                        final startTrailing = startCenterX - baseWidth / 2;
                        final endLeading = endCenterX + baseWidth / 2;
                        final endTrailing = endCenterX - baseWidth / 2;

                        final leadT = Curves.easeOutCubic.transform(t);
                        final trailT = Curves.easeOutBack.transform(t);

                        final currentLeading =
                            lerpDouble(startLeading, endLeading, leadT) ??
                            endLeading;
                        final currentTrailing =
                            lerpDouble(startTrailing, endTrailing, trailT) ??
                            endTrailing;

                        final rawWidth =
                            (currentLeading - currentTrailing).abs();
                        currentWidth = rawWidth.clamp(
                          baseWidth * 0.80,
                          baseWidth * 2.2,
                        );
                        currentCenterX =
                            (currentLeading + currentTrailing) / 2;
                        stretchRatio = ((currentWidth - baseWidth) /
                                baseWidth)
                            .clamp(0.0, 1.0);
                        currentHeight = (baseHeight - stretchRatio * 8.0)
                            .clamp(42.0, baseHeight);
                      } else {
                        // Moving left: left edge is leading, right edge is trailing
                        final startLeading = startCenterX - baseWidth / 2;
                        final startTrailing = startCenterX + baseWidth / 2;
                        final endLeading = endCenterX - baseWidth / 2;
                        final endTrailing = endCenterX + baseWidth / 2;

                        final leadT = Curves.easeOutCubic.transform(t);
                        final trailT = Curves.easeOutBack.transform(t);

                        final currentLeading =
                            lerpDouble(startLeading, endLeading, leadT) ??
                            endLeading;
                        final currentTrailing =
                            lerpDouble(startTrailing, endTrailing, trailT) ??
                            endTrailing;

                        final rawWidth =
                            (currentTrailing - currentLeading).abs();
                        currentWidth = rawWidth.clamp(
                          baseWidth * 0.80,
                          baseWidth * 2.2,
                        );
                        currentCenterX =
                            (currentLeading + currentTrailing) / 2;
                        stretchRatio = ((currentWidth - baseWidth) /
                                baseWidth)
                            .clamp(0.0, 1.0);
                        currentHeight = (baseHeight - stretchRatio * 8.0)
                            .clamp(42.0, baseHeight);
                      }
                    }

                    return Positioned(
                      left: currentCenterX - currentWidth / 2,
                      top: (contentHeight - currentHeight) / 2,
                      width: currentWidth,
                      height: currentHeight,
                      child: CustomPaint(
                        painter: LiquidDropletPainter(
                          borderRadius: currentHeight / 2,
                          isDark: widget.isDark,
                          accentColor: dynamicAccentColor,
                          stretchFactor: stretchRatio,
                        ),
                      ),
                    );
                  },
                ),

                // Nav items
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(navItems.length, (index) {
                    final item = navItems[index];
                    final isSelected = widget.currentIndex == index;

                    return GestureDetector(
                      onTap: () => _onItemTapped(index),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: itemWidth,
                        height: contentHeight,
                        child: AnimatedBuilder(
                          animation: _bounceController,
                          builder: (context, child) {
                            final scale =
                                isSelected && _bounceController.isAnimating
                                    ? _bounceAnimation.value
                                    : 1.0;
                            return Transform.scale(
                              scale: scale,
                              child: _LiquidGlassNavItemWidget(
                                icon: item.$1,
                                selectedIcon: item.$2,
                                label: item.$3,
                                isSelected: isSelected,
                                accentColor: dynamicAccentColor,
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
    );
  }
}

class _LiquidGlassNavItemWidget extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;

  const _LiquidGlassNavItemWidget({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Liquid glass content contrast:
    // Razor-sharp contrast against arbitrary dynamic backdrops.
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : Colors.black.withValues(alpha: 0.55);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isSelected ? selectedIcon : icon,
          size: isSelected ? 25 : 23,
          color: isSelected ? accentColor : unselectedColor,
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: isSelected ? 11.5 : 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? accentColor : unselectedColor,
            letterSpacing: isSelected ? 0.2 : 0,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}
