import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/providers.dart';

/// Swipe-up draggable player sheet
/// Similar to how YouTube Music and Spotify handle the mini player
class SwipeUpPlayerSheet extends ConsumerStatefulWidget {
  final Widget child; // Main content (tabs)
  final Widget miniPlayer;
  final Widget fullPlayer;

  const SwipeUpPlayerSheet({
    super.key,
    required this.child,
    required this.miniPlayer,
    required this.fullPlayer,
  });

  @override
  ConsumerState<SwipeUpPlayerSheet> createState() => _SwipeUpPlayerSheetState();
}

class _SwipeUpPlayerSheetState extends ConsumerState<SwipeUpPlayerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _dragExtent = 0;
  bool _isDragging = false;

  static const double _miniPlayerHeight = 64;
  static const double _velocityThreshold = 300;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _maxExtent =>
      MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;

  bool get _isExpanded => _controller.value > 0.5;

  void _expand() {
    _controller.animateTo(1.0);
  }

  void _collapse() {
    _controller.animateTo(0.0);
  }

  void _handleDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragExtent = _controller.value * _maxExtent;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    _dragExtent -= details.delta.dy;
    _dragExtent = _dragExtent.clamp(0.0, _maxExtent);
    _controller.value = _dragExtent / _maxExtent;
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;

    final velocity = details.velocity.pixelsPerSecond.dy;

    if (velocity.abs() > _velocityThreshold) {
      // Fling
      if (velocity < 0) {
        _expand();
      } else {
        _collapse();
      }
    } else {
      // Snap to nearest state
      if (_controller.value > 0.5) {
        _expand();
      } else {
        _collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final hasTrack = currentTrack != null;
    final bottomPadding = hasTrack
        ? _miniPlayerHeight + MediaQuery.of(context).padding.bottom
        : 0.0;

    return Stack(
      children: [
        // Main content with padding for mini player
        Positioned.fill(bottom: bottomPadding, child: widget.child),

        // Player sheet
        if (hasTrack)
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final sheetHeight =
                  _miniPlayerHeight +
                  _animation.value * (_maxExtent - _miniPlayerHeight);
              final opacity = _animation.value;

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: sheetHeight,
                child: GestureDetector(
                  onVerticalDragStart: _handleDragStart,
                  onVerticalDragUpdate: _handleDragUpdate,
                  onVerticalDragEnd: _handleDragEnd,
                  onTap: _isExpanded ? null : _expand,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16 * (1 - _animation.value)),
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Mini player (fades out as expanded)
                        Opacity(opacity: 1 - opacity, child: widget.miniPlayer),
                        // Full player (fades in as expanded)
                        Opacity(
                          opacity: opacity,
                          child: IgnorePointer(
                            ignoring: !_isExpanded,
                            child: SafeArea(
                              child: Column(
                                children: [
                                  // Drag handle
                                  Container(
                                    width: 40,
                                    height: 4,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade400,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  // Close button
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                      ),
                                      onPressed: _collapse,
                                    ),
                                  ),
                                  // Full player content
                                  Expanded(child: widget.fullPlayer),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Simple mini player bar
class MiniPlayerBar extends ConsumerWidget {
  final VoidCallback? onTap;

  const MiniPlayerBar({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (track == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                        child: const Icon(Iconsax.music, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            // Play/pause button
            IconButton(
              icon: Icon(
                isPlaying ? Iconsax.pause : Iconsax.play,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => playerService.togglePlayPause(),
            ),
            // Next button
            IconButton(
              icon: Icon(
                Iconsax.next,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () => playerService.skipToNext(),
            ),
          ],
        ),
      ),
    );
  }
}
