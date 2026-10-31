import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/liquid_glass/liquid_glass_kit.dart';

/// One destination in [LiquidGlassNav].
class LiquidGlassNavItem {
  const LiquidGlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The app's floating bottom nav — same size, margins and items as the
/// standard one — as shader liquid glass, with the selection pill of the
/// flutter-glass / BitChord tab bar, built the same way:
///
///  - the tabs sit in a [kPillInset] inset inside the bar's glass;
///  - at rest the pill is a flat white fill exactly one tab wide;
///  - switching tabs (or dragging across the bar) lifts it into a clear lens
///    drawn *over* the bar — a sibling of the bar's glass, not inside it, so
///    it can stand taller than the bar — that refracts the bar and the tabs
///    while it travels with squash-and-stretch, then lands back flat
///    ([GlassPillMotion]).
class LiquidGlassNav extends StatefulWidget {
  const LiquidGlassNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.accentColor,
  });

  final List<LiquidGlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  /// Selected icon / label colour (already readable on dark glass).
  final Color accentColor;

  @override
  State<LiquidGlassNav> createState() => _LiquidGlassNavState();
}

class _LiquidGlassNavState extends State<LiquidGlassNav>
    with TickerProviderStateMixin {
  // Same size and corner as the standard nav.
  static const double _barHeight = 64;
  static const double _radius = 32;

  late final GlassPillMotion _pill = GlassPillMotion(
    vsync: this,
    initialIndex: widget.currentIndex,
  );

  double _dragTotal = 0;
  int _dragStartIndex = 0;
  int _lastHapticTab = 0;

  @override
  void initState() {
    super.initState();
    _lastHapticTab = widget.currentIndex;
  }

  @override
  void didUpdateWidget(covariant LiquidGlassNav old) {
    super.didUpdateWidget(old);
    _pill.reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.currentIndex != old.currentIndex) {
      _pill.animateTo(widget.currentIndex);
      _lastHapticTab = widget.currentIndex;
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index != widget.currentIndex) HapticFeedback.selectionClick();
    widget.onTap(index);
  }

  void _endDrag(double tabStep, int n) {
    final next = (_dragStartIndex + _dragTotal / tabStep)
        .clamp(0.0, (n - 1).toDouble())
        .round();
    _pill.release(next);
    if (next != widget.currentIndex) widget.onTap(next);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomMargin = (bottomPadding > 0 ? bottomPadding : 10.0) + 14.0;
    final n = widget.items.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomMargin),
      // Its own repaint boundary: the pill repaints the bar, never the page.
      child: RepaintBoundary(
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowWidth = constraints.maxWidth - kPillInset * 2;
              final tabWidth = rowWidth / n;
              final tabStep = rowWidth / n;
              _pill.stepDp = tabStep;

              final row = Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: _NavItem(
                        item: widget.items[i],
                        selected: i == widget.currentIndex,
                        accent: widget.accentColor,
                        content: glassContentColor(true),
                        onTap: () => _select(i),
                      ),
                    ),
                ],
              );

              return BackdropGroup(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The bar: dark glass in both themes, like the standard
                    // nav, so its white labels read.
                    Positioned.fill(
                      child: LiquidGlass(
                        style: GlassStyle.bitChord(
                          dark: true,
                          surfaceTint: Colors.black.withValues(
                            alpha: widget.isDark ? 0.42 : 0.72,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(_radius),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: (_) {
                            _dragTotal = 0;
                            _dragStartIndex = widget.currentIndex;
                            _pill.startDrag();
                          },
                          onHorizontalDragUpdate: (d) {
                            _dragTotal += d.delta.dx;
                            final pos = (_dragStartIndex + _dragTotal / tabStep)
                                .clamp(0.0, (n - 1).toDouble());
                            _pill.dragTo(pos);
                            final approx = pos.round();
                            if (approx != _lastHapticTab) {
                              HapticFeedback.selectionClick();
                              _lastHapticTab = approx;
                            }
                          },
                          onHorizontalDragEnd: (_) => _endDrag(tabStep, n),
                          onHorizontalDragCancel: () =>
                              _pill.release(widget.currentIndex),
                          child: Padding(
                            padding: const EdgeInsets.all(kPillInset),
                            child: CustomPaint(
                              painter: _FlatPillPainter(
                                motion: _pill,
                                tabWidth: tabWidth,
                                tabStep: tabStep,
                                fill: glassIndicatorColor(true),
                              ),
                              child: row,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The lifted lens, over the bar's glass.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ListenableBuilder(
                          listenable: _pill,
                          builder: (context, _) => _pill.isFlat
                              ? const SizedBox.shrink()
                              : _LiftedPill(
                                  motion: _pill,
                                  tabWidth: tabWidth,
                                  tabStep: tabStep,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Where the pill sits for the current motion frame, in the tab row's
/// coordinates: its centre and its live size (flutter-glass geometry).
(Offset, Size) _pillGeometry(
  GlassPillMotion motion,
  Size rowSize,
  double tabWidth,
  double tabStep,
) {
  final rowHeight = rowSize.height;
  final rest = Size(tabWidth, rowHeight);
  final liftedHeight = rowHeight + kPillInset * 2 + kPillGrowHeight;
  final lifted = rowHeight > 0
      ? Size(liftedHeight * tabWidth / rowHeight, liftedHeight)
      : rest;
  final center = Offset(
    motion.position * tabStep + tabWidth / 2,
    rowHeight / 2,
  );
  return (center, motion.liveSize(rest, lifted));
}

/// The flat pill under the tabs. At rest it is the whole selection; while
/// the lens is up it is the fill the lens refracts, fading out as the
/// material comes on and back in as it goes.
class _FlatPillPainter extends CustomPainter {
  _FlatPillPainter({
    required this.motion,
    required this.tabWidth,
    required this.tabStep,
    required this.fill,
  }) : super(repaint: motion);

  final GlassPillMotion motion;
  final double tabWidth;
  final double tabStep;
  final Color fill;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = fill.a * (1 - motion.material);
    if (alpha <= 0) return;
    final (center, s) = _pillGeometry(motion, size, tabWidth, tabStep);
    final rect = Rect.fromCenter(
      center: center,
      width: s.width,
      height: s.height,
    );
    _paint.color = fill.withValues(alpha: alpha);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      _paint,
    );
  }

  @override
  bool shouldRepaint(_FlatPillPainter old) =>
      old.motion != motion ||
      old.tabWidth != tabWidth ||
      old.tabStep != tabStep ||
      old.fill != fill;
}

/// The lifted pill: a clear lens over the bar that refracts the bar's own
/// glass, the fill and the tab row, with a rim and contact shadow that are
/// the first things shed on landing.
class _LiftedPill extends StatelessWidget {
  const _LiftedPill({
    required this.motion,
    required this.tabWidth,
    required this.tabStep,
  });

  final GlassPillMotion motion;
  final double tabWidth;
  final double tabStep;

  static const double _lensHeight = 12;
  static const double _lensAmount = 14;
  static const GlassShadow _shadow = GlassShadow(
    radius: 12,
    offset: Offset(0, 2),
    color: Color(0x4D000000),
  );

  /// The rim and its shadow are gone by the time the hand-off is 55% done.
  static double _rimOf(double presence) =>
      ((presence - 0.45) / 0.55).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowSize = Size(
          constraints.maxWidth - kPillInset * 2,
          constraints.maxHeight - kPillInset * 2,
        );
        final (center, size) = _pillGeometry(
          motion,
          rowSize,
          tabWidth,
          tabStep,
        );
        final rimAlpha = motion.material * _rimOf(motion.glassPresence);
        final style = GlassStyle(
          refractionHeight: _lensHeight * motion.glassPresence,
          refractionAmount: _lensAmount * motion.material,
          chromaticAberration: true,
          highlight: rimAlpha > 0
              ? GlassHighlight.directional.copyWith(alpha: rimAlpha)
              : null,
          shadow: rimAlpha > 0 ? _shadow.copyWith(alpha: rimAlpha) : null,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: kPillInset + center.dx - size.width / 2,
              top: kPillInset + center.dy - size.height / 2,
              width: math.max(size.width, 1),
              height: math.max(size.height, 1),
              // Over the bar's glass, so it must read its own backdrop.
              child: LiquidGlass(style: style, shareBackdrop: false),
            ),
          ],
        );
      },
    );
  }
}

/// One tab: the standard nav's icon and label, centred in its slot, with the
/// selected glyph riding the pill's spring (flutter-glass `_TabItem`).
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.accent,
    required this.content,
    required this.onTap,
  });

  final LiquidGlassNavItem item;
  final bool selected;
  final Color accent;

  /// Glyph / label colour on the glass: white on dark, black on light.
  final Color content;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  // The glyph rides the same spring as the pill, so the glyph arriving and
  // the glass arriving are one movement.
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? 1.08 : 1,
  );

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      final target = widget.selected ? 1.08 : 1.0;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _scale.value = target;
      } else {
        _scale.animateWith(
          composeSpring(
            _scale.value,
            target,
            _scale.velocity,
            dampingRatio: kGlassSpringDamping,
            stiffness: kGlassSpringStiffness,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected
        ? widget.accent
        : widget.content.withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Center(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 200),
          builder: (context, c, _) => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  selected ? widget.item.selectedIcon : widget.item.icon,
                  size: 23,
                  color: c,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: c,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
