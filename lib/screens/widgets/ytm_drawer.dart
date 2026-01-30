import 'package:flutter/material.dart';

/// YTM-Style velocity-aware two-state drawer
/// Snaps between collapsed (Now Playing) and expanded (Up Next) states
/// based on velocity AND position, matching YouTube Music's feel.
class YTMDrawer extends StatefulWidget {
  /// The Now Playing content (shown when collapsed)
  final Widget nowPlayingContent;

  /// The Up Next content (shown when expanded)
  final Widget upNextContent;

  /// Header for the expanded state (mini player style)
  final Widget? expandedHeader;

  /// Tabs widget (UP NEXT | LYRICS | RELATED) - persists between header and content
  final Widget? tabsWidget;

  /// Background color for the main container
  final Color backgroundColor;

  /// Surface color for the Up Next panel (solid, not transparent)
  final Color surfaceColor;

  /// Callback when state changes
  final ValueChanged<bool>? onStateChanged;

  /// Callback for position-based tab selection (0=left/UP NEXT, 1=center/LYRICS, 2=right/RELATED)
  final ValueChanged<int>? onTabFromPosition;

  /// Initial state
  final bool initiallyExpanded;

  /// Callback when user swipes down while collapsed (for dismiss gesture)
  final VoidCallback? onDismiss;

  const YTMDrawer({
    super.key,
    required this.nowPlayingContent,
    required this.upNextContent,
    this.expandedHeader,
    this.tabsWidget,
    this.backgroundColor = Colors.black,
    this.surfaceColor = const Color(0xFF1A1A1A), // Solid dark surface
    this.onStateChanged,
    this.onTabFromPosition,
    this.initiallyExpanded = false,
    this.onDismiss,
  });

  @override
  State<YTMDrawer> createState() => YTMDrawerState();
}

class YTMDrawerState extends State<YTMDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  /// 0.0 = collapsed (Now Playing visible)
  /// 1.0 = expanded (Up Next visible)
  double _dragProgress = 0.0;

  bool _isDragging = false;
  bool _isExpanded = false;
  double _dragStartX = 0.0; // Track horizontal position for tab selection
  double _dismissDragOffset = 0.0; // Track dismiss drag distance

  /// Constants for snap decision
  static const double _velocityThreshold = 500.0; // px/s
  static const double _positionThreshold = 0.4; // 40% drag to snap
  static const Duration _animDuration = Duration(milliseconds: 280);
  static const Curve _openCurve = Curves.easeOutCubic;
  static const Curve _closeCurve = Curves.easeInCubic;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _dragProgress = _isExpanded ? 1.0 : 0.0;

    _animController = AnimationController(
      vsync: this,
      duration: _animDuration,
      value: _dragProgress,
    );

    _animController.addListener(() {
      setState(() {
        _dragProgress = _animController.value;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Programmatically expand the drawer
  void expand() => _animateTo(1.0, _openCurve);

  /// Programmatically collapse the drawer
  void collapse() => _animateTo(0.0, _closeCurve);

  /// Toggle between states
  void toggle() => _isExpanded ? collapse() : expand();

  /// Expand to specific tab
  void expandToTab(int tabIndex) {
    widget.onTabFromPosition?.call(tabIndex);
    expand();
  }

  void _animateTo(double target, Curve curve) {
    final wasExpanded = _isExpanded;
    _isExpanded = target > 0.5;

    _animController.animateTo(target, duration: _animDuration, curve: curve);

    if (wasExpanded != _isExpanded) {
      widget.onStateChanged?.call(_isExpanded);
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartX = details.globalPosition.dx; // Capture horizontal position
    _animController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final delta = details.primaryDelta ?? 0;

    // Check if user is swiping DOWN while drawer is collapsed - this is dismiss gesture
    if (!_isExpanded && _dragProgress == 0.0 && delta > 0) {
      _dismissDragOffset += delta;
      setState(() {});
      return; // Don't process as drawer expansion
    }

    // Normalize delta to progress (inverted: drag up = increase progress)
    final progressDelta = -delta / screenHeight;

    setState(() {
      _dragProgress = (_dragProgress + progressDelta).clamp(0.0, 1.0);
    });

    _animController.value = _dragProgress;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDragging = false;

    final velocity = details.primaryVelocity ?? 0;

    // Check for dismiss gesture (swiped down while collapsed)
    // Only dismiss if drawer is at 0 progress AND user has been dragging down
    if (_dragProgress == 0.0 && _dismissDragOffset > 0) {
      if (_dismissDragOffset > 100 || velocity > 500) {
        widget.onDismiss?.call();
        _dismissDragOffset = 0;
        return;
      }
    }
    _dismissDragOffset = 0;

    // VELOCITY-AWARE SNAP DECISION (core of YTM feel)
    bool shouldExpand;

    if (velocity.abs() > _velocityThreshold) {
      // Fast flick: snap in direction of velocity
      shouldExpand = velocity < 0; // Negative = dragging up = expand
    } else {
      // Slow drag: snap based on position threshold
      shouldExpand = _dragProgress > _positionThreshold;
    }

    // Position-based tab selection when expanding
    if (shouldExpand && !_isExpanded) {
      final screenWidth = MediaQuery.of(context).size.width;
      final thirdWidth = screenWidth / 3;

      int tabIndex;
      if (_dragStartX < thirdWidth) {
        tabIndex = 0; // Left third → UP NEXT
      } else if (_dragStartX < thirdWidth * 2) {
        tabIndex = 1; // Center third → LYRICS
      } else {
        tabIndex = 2; // Right third → RELATED
      }

      widget.onTabFromPosition?.call(tabIndex);
    }

    _animateTo(
      shouldExpand ? 1.0 : 0.0,
      shouldExpand ? _openCurve : _closeCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate visual transformations based on drag progress
    final albumScale = 1.0 - (_dragProgress * 0.15); // Scale down to 85%
    final backgroundDim = _dragProgress * 0.3; // Darken by 30%
    final upNextOpacity = _dragProgress;
    final nowPlayingOpacity = 1.0 - (_dragProgress * 0.5);

    return GestureDetector(
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Container(
        color: widget.backgroundColor,
        child: Stack(
          children: [
            // Now Playing content (bottom layer)
            Opacity(
              opacity: nowPlayingOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: albumScale,
                alignment: Alignment.topCenter,
                child: widget.nowPlayingContent,
              ),
            ),

            // Dim overlay
            if (_dragProgress > 0)
              Container(color: Colors.black.withValues(alpha: backgroundDim)),

            // Up Next content (slides in from bottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * _dragProgress,
              child: Opacity(
                opacity: upNextOpacity,
                child: Container(
                  // SOLID BACKGROUND for Up Next panel
                  decoration: BoxDecoration(
                    color: widget.surfaceColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Drag handle
                          GestureDetector(
                            onTap: collapse,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white30,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Expanded header (mini player style)
                          if (widget.expandedHeader != null)
                            widget.expandedHeader!,

                          // Tabs bar (UP NEXT | LYRICS | RELATED)
                          if (widget.tabsWidget != null) widget.tabsWidget!,

                          // Tab content - takes remaining space
                          Expanded(
                            child: ClipRect(child: widget.upNextContent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper extension for drawer control
extension YTMDrawerControllerX on GlobalKey<YTMDrawerState> {
  void expand() => currentState?.expand();
  void collapse() => currentState?.collapse();
  void toggle() => currentState?.toggle();
}
