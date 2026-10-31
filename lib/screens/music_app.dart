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
import 'widgets/jiosaavn_notice_sheet.dart';
import 'widgets/liquid_glass_nav.dart';

/// Standalone Music App with its own navigation
class MusicApp extends ConsumerStatefulWidget {
  const MusicApp({super.key});

  @override
  ConsumerState<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends ConsumerState<MusicApp>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  String? _lastTrackedId;
  late AnimationController _animationController;
  late final AnimationController _bottomNavAnimationController;
  late final Animation<double> _bottomNavAnimation;
  bool _isBottomNavVisible = true;
  double _accumulatedDelta = 0.0;
  static const double _hideThreshold = 25.0;
  static const double _showThreshold = 20.0;

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
    _bottomNavAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _bottomNavAnimation = CurvedAnimation(
      parent: _bottomNavAnimationController,
      curve: Curves.easeInOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) await JioSaavnNoticeSheet.maybeShow(context, ref);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _bottomNavAnimationController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final delta = notification.scrollDelta;
      if (delta == null || delta == 0) return false;

      // When near or at top, always reveal bottom navbar
      if (metrics.pixels <= 15.0) {
        if (!_isBottomNavVisible) {
          _isBottomNavVisible = true;
          _bottomNavAnimationController.forward();
        }
        _accumulatedDelta = 0.0;
        return false;
      }

      // Avoid toggling when overscrolling past bottom or top extent
      if (metrics.pixels > metrics.maxScrollExtent || metrics.pixels < 0) {
        return false;
      }

      // When near bottom, reveal nav so user can navigate
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 20.0) {
        if (!_isBottomNavVisible) {
          _isBottomNavVisible = true;
          _bottomNavAnimationController.forward();
        }
        _accumulatedDelta = 0.0;
        return false;
      }

      if (delta > 0) {
        // Scrolling DOWN -> hide bottom navbar
        if (_accumulatedDelta < 0) _accumulatedDelta = 0;
        _accumulatedDelta += delta;
        if (_accumulatedDelta > _hideThreshold && _isBottomNavVisible) {
          _isBottomNavVisible = false;
          _bottomNavAnimationController.reverse();
          _accumulatedDelta = 0;
        }
      } else if (delta < 0) {
        // Scrolling UP -> reveal bottom navbar
        if (_accumulatedDelta > 0) _accumulatedDelta = 0;
        _accumulatedDelta += delta;
        if (_accumulatedDelta < -_showThreshold && !_isBottomNavVisible) {
          _isBottomNavVisible = true;
          _bottomNavAnimationController.forward();
          _accumulatedDelta = 0;
        }
      }
    }
    return false;
  }

  void _onTabSelected(int index) {
    if (!_isBottomNavVisible) {
      _isBottomNavVisible = true;
      _bottomNavAnimationController.forward();
    }
    _accumulatedDelta = 0.0;
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
        body: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: Stack(
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
                      AnimatedBuilder(
                        animation: _bottomNavAnimation,
                        builder: (context, child) {
                          final safeBottom =
                              MediaQuery.of(context).padding.bottom;
                          final extraBottom = (1.0 - _bottomNavAnimation.value) *
                              (safeBottom > 0 ? safeBottom + 4 : 12.0);
                          return Padding(
                            padding: EdgeInsets.only(bottom: extraBottom),
                            child: child,
                          );
                        },
                        child: MusicMiniPlayer(
                          onTap: () => NowPlayingScreen.show(context),
                        ),
                      ),
                    // Clips the hide animation, but lets the glass nav's
                    // lifted lens rise above the bar's top edge.
                    ClipRect(
                      clipper: const _TopOverflowClipper(16),
                      // SizeTransition's own animation without its built-in
                      // ClipRect, which cut the lens off at the bar's edge.
                      child: AnimatedBuilder(
                        animation: _bottomNavAnimation,
                        builder: (context, child) => Align(
                          alignment: Alignment.topCenter,
                          heightFactor: _bottomNavAnimation.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                        child: FadeTransition(
                          opacity: _bottomNavAnimation,
                          child: _ModernFloatingNav(
                            currentIndex: _currentIndex,
                            onTap: _onTabSelected,
                            isDark: isDark,
                            accentColor: accentColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating bottom navigation (the liquid glass bar is built separately,
/// see _MusicAppState._buildGlassTabBar).
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
    if (ref.watch(liquidGlassNavProvider)) {
      final l10n = context.l10n;
      final albumColors = ref.watch(albumColorsProvider);
      // The bar is dark glass in both themes, so the accent must read on dark.
      final accent = readableAccent(
        albumColors.isDefault ? accentColor : albumColors.accent,
        isDark: true,
      );
      return LiquidGlassNav(
        items: [
          LiquidGlassNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: l10n.home,
          ),
          LiquidGlassNavItem(
            icon: Icons.music_note_outlined,
            selectedIcon: Icons.music_note_rounded,
            label: l10n.songs,
          ),
          LiquidGlassNavItem(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: l10n.library,
          ),
          LiquidGlassNavItem(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder_rounded,
            label: l10n.folders,
          ),
        ],
        currentIndex: currentIndex,
        onTap: onTap,
        isDark: isDark,
        accentColor: accent,
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
    // The bar is dark glass in both themes, so the accent must read on dark
    // (a black accent would otherwise vanish).
    final dynamicAccentColor = readableAccent(
      hasAlbumColors ? albumColors.accent : widget.accentColor,
      isDark: true,
    );

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


/// A [ClipRect] clip extended [overflow] px above the child, so content that
/// rises out of the top of the bar (the liquid glass nav's lifted lens) is
/// not cut off.
class _TopOverflowClipper extends CustomClipper<Rect> {
  const _TopOverflowClipper(this.overflow);

  final double overflow;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -overflow, size.width, size.height);

  @override
  bool shouldReclip(covariant _TopOverflowClipper oldClipper) =>
      oldClipper.overflow != overflow;
}
