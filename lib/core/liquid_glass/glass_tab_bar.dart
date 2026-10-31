import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_spring.dart';
import 'glass_pill_motion.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

class GlassTab {
  const GlassTab({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// The gap between the bar's glass edge and the tabs inside it.
const double kPillInset = 6;

/// Each tab's own vertical padding.
const double kTabVerticalPadding = 9;

/// The gap between a tab's glyph and its label.
const double kTabIconLabelGap = 2;

/// How much taller than the bar the selection pill stands while lifted.
const double kPillGrowHeight = 9;

/// BitChord's `GlassSpring`: damping 0.72, stiffness 320.
const double kGlassSpringDamping = 0.72;
const double kGlassSpringStiffness = 320;

/// Glyph and label colour on glass: pure black or white off the theme.
Color glassContentColor(bool dark) => dark ? Colors.white : Colors.black;

/// The selected tab's fill: white in both themes, a step whiter than the
/// bar in dark theme.
Color glassIndicatorColor(bool dark) =>
    dark ? const Color(0x24FFFFFF) : const Color(0x80FFFFFF);

/// The now-playing accessory that rides with the bar — what BitChord's
/// `GlassNowPlaying` shows.
@immutable
class GlassAccessory {
  const GlassAccessory({
    required this.title,
    required this.artist,
    required this.artwork,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    this.onTap,
  });

  final String title;
  final String artist;
  final Widget artwork;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback? onTap;
}

/// The inline row's height: a 25dp glyph inside the inline tab's 10dp padding.
const double kInlineBarHeight = 25 + 10 * 2;

/// The gap between the bar's components (FloatingTabBar's componentSpacing).
const double kComponentSpacing = 8;

/// Material 3 line heights the accessory's text is set on (titleMedium,
/// bodyMedium), which make the expanded accessory taller than its art.
const double _titleSize = 16, _titleLine = 24;
const double _artistSize = 14, _artistLine = 20;

/// BitChord's `GlassNavBar` (its vendored iOS 26 `FloatingTabBar`): a
/// capsule of liquid glass holding the tabs, a circular standalone tab
/// beside it, an optional now-playing accessory above, and the selection
/// pill that lifts out of the bar as a lens while it travels.
///
/// With [inline] set (BitChord sets it on scrolling down) the bar collapses
/// into one row — the selected tab's circle, the accessory, the standalone
/// tab — every surface morphing its bounds on Compose's default
/// shared-element spring while the contents crossfade, and the selected
/// glyph travelling into its circle.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.dark,
    this.standaloneIcon,
    this.onStandaloneTap,
    this.accessory,
    this.inline = false,
    this.onExpand,
    this.chromaticAberration = true,
    this.reduceMotion = false,
  });

  final List<GlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool dark;
  final IconData? standaloneIcon;
  final VoidCallback? onStandaloneTap;
  final GlassAccessory? accessory;
  final bool inline;

  /// The inline tab was tapped: the bar should expand again.
  final VoidCallback? onExpand;
  final bool chromaticAberration;
  final bool reduceMotion;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with TickerProviderStateMixin {
  late final GlassPillMotion _pill =
      GlassPillMotion(vsync: this, initialIndex: widget.selectedIndex);

  /// 0 expanded, 1 inline.
  late final AnimationController _inline = AnimationController.unbounded(
    vsync: this,
    value: widget.inline ? 1 : 0,
  );

  /// The accessory's press scale: 1.04 while held, no bounce, stiffness 400.
  late final AnimationController _accessoryScale =
      AnimationController.unbounded(vsync: this, value: 1);

  /// The collapse progress. A settled spring lands within its tolerance of
  /// the target, not on it, so the resting states are snapped exact —
  /// pointer routing and the pill key off them.
  double get _inlineT {
    final t = _inline.value.clamp(0.0, 1.0);
    if (t < 1e-3) return 0;
    if (t > 1 - 1e-3) return 1;
    return t;
  }

  double _dragTotal = 0;
  int _dragStartIndex = 0;
  int _lastHapticTab = 0;

  @override
  void initState() {
    super.initState();
    _lastHapticTab = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(GlassTabBar old) {
    super.didUpdateWidget(old);
    _pill.reduceMotion = widget.reduceMotion;
    if (widget.selectedIndex != old.selectedIndex) {
      if (_inlineT > 0) {
        _pill.snapTo(widget.selectedIndex);
      } else {
        _pill.animateTo(widget.selectedIndex);
      }
      _lastHapticTab = widget.selectedIndex;
    }
    if (widget.inline != old.inline) {
      final target = widget.inline ? 1.0 : 0.0;
      if (widget.reduceMotion) {
        _inline.value = target;
      } else {
        _inline.animateWith(composeSpring(
          _inline.value,
          target,
          _inline.velocity,
          dampingRatio: 1,
          stiffness: 400,
        ));
      }
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    _inline.dispose();
    _accessoryScale.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index != widget.selectedIndex) HapticFeedback.selectionClick();
    widget.onTabSelected(index);
  }

  void _pressAccessory(double target) {
    _accessoryScale.animateWith(composeSpring(
      _accessoryScale.value,
      target,
      _accessoryScale.velocity,
      dampingRatio: 1,
      stiffness: 400,
    ));
  }

  @override
  Widget build(BuildContext context) {
    _pill.reduceMotion = widget.reduceMotion;
    final barStyle = GlassStyle.bitChord(
      dark: widget.dark,
      surfaceTint: GlassStyle.bitChordBarTint(dark: widget.dark),
      chromaticAberration: widget.chromaticAberration,
    );

    // A fixed height (the tab's own padding, glyph, gap and one strut-forced
    // label line, inside the inset) so the standalone tab can be a circle
    // exactly as tall as the bar without an intrinsic-size pass.
    final labelHeight = MediaQuery.textScalerOf(context).scale(11) * 1.2;
    final barHeight = kPillInset * 2 +
        kTabVerticalPadding * 2 +
        25 +
        kTabIconLabelGap +
        labelHeight;
    final scaler = MediaQuery.textScalerOf(context);
    final accessoryHeight = math.max(
          40.0,
          scaler.scale(_titleLine) + scaler.scale(_artistLine),
        ) +
        8 * 2;

    // Its own repaint boundary: the pill and the morph repaint the bar,
    // never the page behind it.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _inline,
          builder: (context, _) =>
              _morph(constraints.maxWidth, barHeight, accessoryHeight, barStyle),
        ),
      ),
    );
  }

  Widget _morph(
    double width,
    double barHeight,
    double accessoryHeight,
    GlassStyle style,
  ) {
    final t = _inlineT;
    final hasAccessory = widget.accessory != null;
    final hasStandalone = widget.standaloneIcon != null;

    // Expanded: the accessory over a row of the tab group and the
    // standalone circle.
    final eTop = hasAccessory ? accessoryHeight + kComponentSpacing : 0.0;
    final eHeight = eTop + barHeight;
    final eGroup = Rect.fromLTWH(0, eTop,
        width - (hasStandalone ? barHeight + kComponentSpacing : 0), barHeight);
    final eStandalone = Rect.fromLTWH(width - barHeight, eTop, barHeight, barHeight);
    final eAccessory = Rect.fromLTWH(0, 0, width, accessoryHeight);

    // Inline: one row, centred when there is no accessory to fill it.
    const h = kInlineBarHeight;
    final standaloneW = hasStandalone ? h + kComponentSpacing : 0.0;
    final accessoryW =
        hasAccessory ? width - h - kComponentSpacing - standaloneW : 0.0;
    final rowW = hasAccessory ? width : h + standaloneW;
    final x0 = (width - rowW) / 2;
    final iGroup = Rect.fromLTWH(x0, 0, h, h);
    final iAccessory = Rect.fromLTWH(x0 + h + kComponentSpacing, 0, accessoryW, h);
    final iStandalone = Rect.fromLTWH(x0 + rowW - h, 0, h, h);

    // Bottom-anchored, as AnimatedContent is aligned BottomCenter.
    final height = lerpDouble(eHeight, h, t)!;
    Rect morph(Rect e, Rect i) {
      final w = lerpDouble(e.width, i.width, t)!;
      final hh = lerpDouble(e.height, i.height, t)!;
      final fromBottom =
          lerpDouble(eHeight - e.bottom, h - i.bottom, t)!;
      return Rect.fromLTWH(
          lerpDouble(e.left, i.left, t)!, height - fromBottom - hh, w, hh);
    }

    final group = morph(eGroup, iGroup);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasAccessory)
            Positioned.fromRect(
              rect: morph(eAccessory, iAccessory),
              child: _accessory(style, t, eAccessory.size, iAccessory.size),
            ),
          Positioned.fromRect(
            rect: group,
            child: _tabGroup(style, t, eGroup.size, group.size),
          ),
          if (hasStandalone)
            Positioned.fromRect(
              rect: morph(eStandalone, iStandalone),
              child: _StandaloneTab(
                icon: widget.standaloneIcon!,
                color: glassContentColor(widget.dark).withValues(alpha: 0.65),
                style: style,
                onTap: widget.onStandaloneTap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabGroup(GlassStyle style, double t, Size expanded, Size live) {
    final content = glassContentColor(widget.dark);
    final n = widget.tabs.length;
    final rowWidth = expanded.width - kPillInset * 2;
    final tabWidth = rowWidth / n;
    final tabStep = rowWidth / n;
    _pill.stepDp = tabStep;

    final row = Row(
      children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: _TabItem(
              tab: widget.tabs[i],
              selected: i == widget.selectedIndex,
              selectedColor: content,
              unselectedColor: content.withValues(alpha: 0.65),
              reduceMotion: widget.reduceMotion,
              hideIcon: t > 0 && i == widget.selectedIndex,
              onTap: () => _select(i),
            ),
          ),
      ],
    );

    // The selected glyph is shared between the states: it travels from its
    // place in the row to the centre of the inline circle.
    final sel = widget.selectedIndex;
    final from = Offset(kPillInset + (sel + 0.5) * tabWidth,
        kPillInset + kTabVerticalPadding + 12.5);
    final to = Offset(live.width / 2, live.height / 2);
    final glyph = Offset.lerp(from, to, t)!;

    final expandedContent = IgnorePointer(
      ignoring: t > 0,
      child: Opacity(
        opacity: 1 - t,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: expanded.width,
          maxWidth: expanded.width,
          minHeight: expanded.height,
          maxHeight: expanded.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _dragTotal = 0;
              _dragStartIndex = widget.selectedIndex;
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
            onHorizontalDragCancel: () => _pill.release(widget.selectedIndex),
            child: Padding(
              padding: const EdgeInsets.all(kPillInset),
              child: CustomPaint(
                painter: _FlatPillPainter(
                  motion: _pill,
                  tabWidth: tabWidth,
                  tabStep: tabStep,
                  fill: glassIndicatorColor(widget.dark),
                ),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: LiquidGlass(
            style: style,
            child: Stack(
              children: [
                Positioned.fill(child: expandedContent),
                if (t > 0)
                  Positioned(
                    left: glyph.dx - 12.5,
                    top: glyph.dy - 12.5,
                    width: 25,
                    height: 25,
                    child: Transform.scale(
                      scale: lerpDouble(1.08, 1, t)!,
                      child: Icon(widget.tabs[sel].icon, size: 25, color: content),
                    ),
                  ),
                if (t > 0.5)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onExpand?.call();
                        widget.onTabSelected(sel);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (t == 0)
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
                        chromaticAberration: widget.chromaticAberration,
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _accessory(GlassStyle style, double t, Size expanded, Size inline) {
    final a = widget.accessory!;
    final content = glassContentColor(widget.dark);
    Widget state(Size size, double opacity, Widget child) => IgnorePointer(
          ignoring: opacity < 0.5,
          child: Opacity(
            opacity: opacity,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: size.width,
              maxWidth: size.width,
              minHeight: size.height,
              maxHeight: size.height,
              child: child,
            ),
          ),
        );
    return Listener(
      onPointerDown: (_) => _pressAccessory(1.04),
      onPointerUp: (_) => _pressAccessory(1),
      onPointerCancel: (_) => _pressAccessory(1),
      child: GestureDetector(
        onTap: a.onTap,
        child: ScaleTransition(
          scale: _accessoryScale,
          child: LiquidGlass(
            style: style,
            child: Stack(
              children: [
                if (t < 1)
                  Positioned.fill(
                    child: state(expanded, 1 - t,
                        _AccessoryContent(accessory: a, inline: false, color: content)),
                  ),
                if (t > 0)
                  Positioned.fill(
                    child: state(inline, t,
                        _AccessoryContent(accessory: a, inline: true, color: content)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag(double tabStep, int n) {
    final newIndex = (_dragStartIndex + _dragTotal / tabStep)
        .clamp(0.0, (n - 1).toDouble())
        .round();
    _pill.release(newIndex);
    if (newIndex != widget.selectedIndex) widget.onTabSelected(newIndex);
  }
}

/// Where the pill sits for the current motion frame, in the tab row's
/// coordinates: its centre and its live size.
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
  final center = Offset(motion.position * tabStep + tabWidth / 2, rowHeight / 2);
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
    final rect = Rect.fromCenter(center: center, width: s.width, height: s.height);
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
    required this.chromaticAberration,
  });

  final GlassPillMotion motion;
  final double tabWidth;
  final double tabStep;
  final bool chromaticAberration;

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
    return LayoutBuilder(builder: (context, constraints) {
      final rowSize = Size(
        constraints.maxWidth - kPillInset * 2,
        constraints.maxHeight - kPillInset * 2,
      );
      final (center, size) = _pillGeometry(motion, rowSize, tabWidth, tabStep);
      final rimAlpha = motion.material * _rimOf(motion.glassPresence);
      final style = GlassStyle(
        refractionHeight: _lensHeight * motion.glassPresence,
        refractionAmount: _lensAmount * motion.material,
        chromaticAberration: chromaticAberration,
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
    });
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.reduceMotion,
    required this.onTap,
    this.hideIcon = false,
  });

  final GlassTab tab;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final bool reduceMotion;
  final VoidCallback onTap;

  /// While the bar morphs, the selected glyph is drawn travelling instead.
  final bool hideIcon;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> with SingleTickerProviderStateMixin {
  // The glyph rides the same spring as the pill, so the glyph arriving and
  // the glass arriving are one movement.
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? 1.08 : 1,
  );

  @override
  void didUpdateWidget(_TabItem old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      final target = widget.selected ? 1.08 : 1.0;
      if (widget.reduceMotion) {
        _scale.value = target;
      } else {
        _scale.animateWith(composeSpring(
          _scale.value,
          target,
          _scale.velocity,
          dampingRatio: kGlassSpringDamping,
          stiffness: kGlassSpringStiffness,
        ));
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
    final color = widget.selected ? widget.selectedColor : widget.unselectedColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kTabVerticalPadding),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 200),
          builder: (context, c, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: widget.hideIcon ? 0 : 1,
                child: ScaleTransition(
                  scale: _scale,
                  child: Icon(widget.tab.icon, size: 25, color: c),
                ),
              ),
              const SizedBox(height: kTabIconLabelGap),
              Text(
                widget.tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                strutStyle: const StrutStyle(
                  fontSize: 11,
                  height: 1.2,
                  forceStrutHeight: true,
                ),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandaloneTab extends StatelessWidget {
  const _StandaloneTab({
    required this.icon,
    required this.color,
    required this.style,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final GlassStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        style: style,
        child: Center(child: Icon(icon, size: 25, color: color)),
      ),
    );
  }
}

/// BitChord's `GlassNowPlaying` content in either state: expanded is 40dp
/// art with rounded corners, title over artist, play/pause and next;
/// inline is 32dp round art, the title, and play/pause.
class _AccessoryContent extends StatelessWidget {
  const _AccessoryContent({
    required this.accessory,
    required this.inline,
    required this.color,
  });

  final GlassAccessory accessory;
  final bool inline;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final a = accessory;
    final art = inline ? 32.0 : 40.0;
    final glyphSlot = inline ? 32.0 : 40.0;
    final glyph = inline ? 24.0 : 32.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: inline ? 8 : 12,
        vertical: inline ? 4 : 8,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(inline ? art / 2 : 8),
            child: SizedBox(width: art, height: art, child: a.artwork),
          ),
          SizedBox(width: inline ? 8 : 10),
          Expanded(
            child: inline
                ? Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: _titleSize,
                      height: _titleLine / _titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: _titleSize,
                          height: _titleLine / _titleSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        a.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: _artistSize,
                          height: _artistLine / _artistSize,
                        ),
                      ),
                    ],
                  ),
          ),
          _GlyphButton(
            icon: a.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: color,
            slot: glyphSlot,
            size: glyph,
            onTap: a.onPlayPause,
          ),
          if (!inline) ...[
            const SizedBox(width: 8),
            _GlyphButton(
              icon: Icons.fast_forward_rounded,
              color: color,
              slot: glyphSlot,
              size: glyph,
              onTap: a.onNext,
            ),
          ],
        ],
      ),
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.color,
    required this.slot,
    required this.size,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final double slot;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: slot,
        height: slot,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
