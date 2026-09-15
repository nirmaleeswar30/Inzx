import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../core/providers/theme_provider.dart';
import '../../services/canvas/canvas_artwork.dart';
import '../../services/canvas/canvas_repository.dart';

/// Renders looping animated motion artwork (Canvas) over the static album art.
///
/// Features:
/// - Pre-caches video files to disk via [DefaultCacheManager] to eliminate network
///   buffering on loops and save mobile data.
/// - Layered presentation: Static album artwork is always rendered underneath,
///   and the video smoothly fades in (400ms) only once its first frame is ready.
/// - Playback sync: Automatically pauses video rendering when audio playback is
///   paused to conserve battery and GPU resources.
/// - Safe disposal: Disposes VideoPlayerController immediately on track changes
///   or unmount.
class AnimatedAlbumArtView extends ConsumerStatefulWidget {
  final Track track;
  final Widget staticArt;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final void Function(bool hasCanvas)? onCanvasLoaded;

  const AnimatedAlbumArtView({
    super.key,
    required this.track,
    required this.staticArt,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
    this.onCanvasLoaded,
  });

  @override
  ConsumerState<AnimatedAlbumArtView> createState() =>
      _AnimatedAlbumArtViewState();
}

class _AnimatedAlbumArtViewState extends ConsumerState<AnimatedAlbumArtView> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadCanvas();
  }

  @override
  void didUpdateWidget(covariant AnimatedAlbumArtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.title != widget.track.title) {
      _stopAndReset();
      _loadCanvas();
    }
  }

  void _disposeController(VideoPlayerController? controller) {
    if (controller == null) return;
    try {
      controller.pause();
    } catch (_) {}
    try {
      controller.dispose();
    } catch (_) {}
  }

  void _stopAndReset({bool notifyState = true}) {
    _loadRequestId++;
    final oldController = _controller;
    _controller = null;
    _isInitialized = false;
    if (notifyState && mounted) {
      setState(() {});
    }
    _disposeController(oldController);
  }

  Future<void> _loadCanvas() async {
    final isEnabled = ref.read(animatedAlbumArtProvider);
    if (!isEnabled) {
      widget.onCanvasLoaded?.call(false);
      return;
    }

    final currentRequestId = ++_loadRequestId;
    final trackTitle = widget.track.title;
    final trackArtist = widget.track.artist;

    widget.onCanvasLoaded?.call(false);
    debugPrint('AnimatedAlbumArt: Checking canvas for "$trackTitle" by "$trackArtist"...');

    try {
      final canvas = await CanvasRepository.instance.canvasFor(widget.track);
      if (!mounted || currentRequestId != _loadRequestId) return;

      if (canvas == null) {
        debugPrint('AnimatedAlbumArt: No animated canvas available for "$trackTitle". Showing static artwork.');
        widget.onCanvasLoaded?.call(false);
        return;
      }

      debugPrint('AnimatedAlbumArt: Found canvas from ${canvas.source.name} for "$trackTitle". Loading video...');
      widget.onCanvasLoaded?.call(true);
      await _setupVideo(canvas, currentRequestId);
    } catch (e) {
      debugPrint('AnimatedAlbumArt: Error resolving canvas for "$trackTitle": $e');
      if (mounted && currentRequestId == _loadRequestId) {
        widget.onCanvasLoaded?.call(false);
      }
    }
  }

  Future<VideoPlayerController> _createController(
    String url,
    CanvasSource source,
  ) async {
    final uri = Uri.parse(url);
    final isHls =
        url.toLowerCase().contains('.m3u8') || source == CanvasSource.appleMusic;

    if (isHls) {
      // HLS (.m3u8) streams must be streamed natively over HTTP
      return VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }

    // Direct MP4 clips (Tidal / Community): attempt pre-caching to disk
    try {
      final File cachedVideoFile = await DefaultCacheManager()
          .getSingleFile(url)
          .timeout(const Duration(seconds: 8));
      return VideoPlayerController.file(
        cachedVideoFile,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    } catch (e) {
      debugPrint(
        'AnimatedAlbumArt: Cache download failed ($e), falling back to network stream',
      );
      return VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }
  }

  Future<void> _setupVideo(CanvasArtwork canvas, int requestId) async {
    VideoPlayerController? controller;

    try {
      controller = await _createController(canvas.url, canvas.source);

      if (!mounted || requestId != _loadRequestId) {
        await controller.dispose();
        return;
      }

      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);

      if (!mounted || requestId != _loadRequestId) {
        await controller.dispose();
        return;
      }

      final old = _controller;
      _controller = controller;
      _disposeController(old);

      // Sync with active playback state
      final isPlaying = ref.read(isPlayingProvider);
      if (isPlaying) {
        await controller.play();
      } else {
        await controller.pause();
      }

      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _isInitialized = true;
        });
      }

      debugPrint('AnimatedAlbumArt: Video player active and looping for "${widget.track.title}"');
      return;
    } catch (e) {
      debugPrint('AnimatedAlbumArt: Primary video init failed: $e');
      if (controller != null) {
        await controller.dispose();
      }
    }

    // Attempt fallback URL if provided
    if (canvas.fallbackUrl != null) {
      VideoPlayerController? fallbackController;
      try {
        fallbackController =
            await _createController(canvas.fallbackUrl!, canvas.source);
        if (!mounted || requestId != _loadRequestId) {
          await fallbackController.dispose();
          return;
        }

        await fallbackController.initialize();
        await fallbackController.setLooping(true);
        await fallbackController.setVolume(0.0);

        if (!mounted || requestId != _loadRequestId) {
          await fallbackController.dispose();
          return;
        }

        final old = _controller;
        _controller = fallbackController;
        _disposeController(old);

        final isPlaying = ref.read(isPlayingProvider);
        if (isPlaying) {
          await fallbackController.play();
        } else {
          await fallbackController.pause();
        }

        if (mounted && requestId == _loadRequestId) {
          setState(() {
            _isInitialized = true;
          });
        }
      } catch (e) {
        debugPrint('AnimatedAlbumArt: Fallback video init failed: $e');
        if (fallbackController != null) {
          await fallbackController.dispose();
        }
      }
    }
  }

  @override
  void dispose() {
    _stopAndReset(notifyState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = ref.watch(animatedAlbumArtProvider);
    if (!isEnabled) {
      return widget.staticArt;
    }

    // Sync play/pause with player service state
    ref.listen<bool>(isPlayingProvider, (previous, isPlaying) {
      if (!mounted) return;
      if (_controller != null && _isInitialized) {
        if (isPlaying) {
          _controller!.play();
        } else {
          _controller!.pause();
        }
      }
    });

    // Listen for settings toggle changes dynamically
    ref.listen<bool>(animatedAlbumArtProvider, (previous, enabled) {
      if (!mounted) return;
      if (enabled) {
        _loadCanvas();
      } else {
        _stopAndReset();
      }
    });

    final controller = _controller;
    final hasActiveVideo = controller != null && _isInitialized;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Layer 1: Static Art (Immediate 0ms fallback)
        widget.staticArt,

        // Layer 2: Animated Looping Video Canvas
        if (hasActiveVideo)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: AnimatedOpacity(
                opacity: _isInitialized ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: controller.value.size.width > 0
                          ? controller.value.size.width
                          : 1280,
                      height: controller.value.size.height > 0
                          ? controller.value.size.height
                          : 1280,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
