import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../providers/providers.dart';

/// Top-level isolate function for fast image decoding
img.Image? _decodeImageSync(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

/// Parameters for crop operation in isolate
class _CropParams {
  final Uint8List rawBytes;
  final int cropX;
  final int cropY;
  final int cropSize;

  _CropParams({
    required this.rawBytes,
    required this.cropX,
    required this.cropY,
    required this.cropSize,
  });
}

/// Top-level isolate function for crop and resize
Uint8List? _cropAndEncodeSync(_CropParams params) {
  try {
    final decoded = img.decodeImage(params.rawBytes);
    if (decoded == null) return null;

    final cropped = img.copyCrop(
      decoded,
      x: params.cropX,
      y: params.cropY,
      width: params.cropSize,
      height: params.cropSize,
    );

    final resized = cropped.width > 1024
        ? img.copyResize(
            cropped,
            width: 1024,
            height: 1024,
            interpolation: img.Interpolation.cubic,
          )
        : cropped;

    return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
  } catch (_) {
    return null;
  }
}

/// An interactive, full-screen 1:1 square image cropper for YouTube Music playlist covers.
/// Supports pan and pinch-to-zoom with boundary snapping and centered default framing.
class SquareImageCropper extends ConsumerStatefulWidget {
  final Uint8List imageBytes;

  const SquareImageCropper({
    super.key,
    required this.imageBytes,
  });

  @override
  ConsumerState<SquareImageCropper> createState() => _SquareImageCropperState();
}

class _SquareImageCropperState extends ConsumerState<SquareImageCropper> {
  img.Image? _decodedImage;
  bool _loading = true;
  bool _cropping = false;

  // Viewport and image layout
  double _viewportSize = 320.0;
  Offset _viewportCenter = Offset.zero;
  Rect get _cropRect => Rect.fromCenter(
        center: _viewportCenter,
        width: _viewportSize,
        height: _viewportSize,
      );

  // Transform state
  double _scale = 1.0;
  double _imgLeft = 0.0;
  double _imgTop = 0.0;

  // Gesture tracking
  double _baseScale = 1.0;
  double _dispW = 0.0;
  double _dispH = 0.0;

  double _startScale = 1.0;
  Offset _startFocalPoint = Offset.zero;
  double _startImgLeft = 0.0;
  double _startImgTop = 0.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final decoded = await compute(_decodeImageSync, widget.imageBytes);
    if (!mounted) return;
    setState(() {
      _decodedImage = decoded;
      _loading = false;
    });
  }

  void _initTransform(Size screenSize) {
    if (_decodedImage == null) return;

    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();

    // Determine viewport size (square fitting screen width with margin)
    _viewportSize = min(screenSize.width - 40, screenSize.height - 240).clamp(240.0, 380.0);
    // Position viewport in upper-middle of screen
    _viewportCenter = Offset(screenSize.width / 2, (screenSize.height - 80) / 2);

    // Base scale to cover the square viewport (BoxFit.cover)
    _baseScale = max(_viewportSize / imgW, _viewportSize / imgH);
    _dispW = imgW * _baseScale;
    _dispH = imgH * _baseScale;

    _scale = 1.0;
    // Centered by default
    _imgLeft = _cropRect.left - (_dispW - _viewportSize) / 2;
    _imgTop = _cropRect.top - (_dispH - _viewportSize) / 2;
  }

  void _clampPosition() {
    final curW = _dispW * _scale;
    final curH = _dispH * _scale;

    final minX = _cropRect.right - curW;
    final maxX = _cropRect.left;
    final minY = _cropRect.bottom - curH;
    final maxY = _cropRect.top;

    _imgLeft = _imgLeft.clamp(minX, maxX);
    _imgTop = _imgTop.clamp(minY, maxY);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startFocalPoint = details.localFocalPoint;
    _startImgLeft = _imgLeft;
    _startImgTop = _imgTop;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      final newScale = (_startScale * details.scale).clamp(1.0, 4.0);

      // Zoom around the focal point
      final fp = details.localFocalPoint;
      final focalOnImageX = (fp.dx - _startImgLeft) / _startScale;
      final focalOnImageY = (fp.dy - _startImgTop) / _startScale;

      _scale = newScale;
      _imgLeft = fp.dx - focalOnImageX * newScale + (details.localFocalPoint.dx - _startFocalPoint.dx);
      _imgTop = fp.dy - focalOnImageY * newScale + (details.localFocalPoint.dy - _startFocalPoint.dy);

      _clampPosition();
    });
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _imgLeft = _cropRect.left - (_dispW - _viewportSize) / 2;
      _imgTop = _cropRect.top - (_dispH - _viewportSize) / 2;
      _clampPosition();
    });
  }

  Future<void> _done() async {
    if (_decodedImage == null || _cropping) return;

    setState(() => _cropping = true);

    final imgW = _decodedImage!.width;
    final imgH = _decodedImage!.height;
    final curW = _dispW * _scale;
    final pixelScale = curW / imgW;

    final relX = _cropRect.left - _imgLeft;
    final relY = _cropRect.top - _imgTop;

    int sourceX = (relX / pixelScale).round().clamp(0, imgW - 1);
    int sourceY = (relY / pixelScale).round().clamp(0, imgH - 1);
    int sourceSize = (_viewportSize / pixelScale).round();
    sourceSize = min(sourceSize, min(imgW - sourceX, imgH - sourceY));

    final croppedBytes = await compute(
      _cropAndEncodeSync,
      _CropParams(
        rawBytes: widget.imageBytes,
        cropX: sourceX,
        cropY: sourceY,
        cropSize: sourceSize,
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, croppedBytes ?? widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(effectiveAccentColorProvider);
    final screenSize = MediaQuery.sizeOf(context);

    if (_viewportCenter == Offset.zero && _decodedImage != null) {
      _initTransform(screenSize);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _decodedImage == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_rounded,
                            color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Could not load image',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      // Interactive image area
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onDoubleTap: () {
                          if (_scale > 1.1) {
                            _reset();
                          } else {
                            setState(() {
                              _scale = 2.0;
                              _clampPosition();
                            });
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          children: [
                            // Scaled & translated image
                            Positioned(
                              left: _imgLeft,
                              top: _imgTop,
                              width: _dispW * _scale,
                              height: _dispH * _scale,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                            // Mask and border overlay
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CropOverlayPainter(
                                  cropRect: _cropRect,
                                  accentColor: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Top App Bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Crop Playlist Cover',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Pinch to zoom, drag to position',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_scale > 1.05 ||
                                  (_imgLeft -
                                              (_cropRect.left -
                                                  (_dispW - _viewportSize) /
                                                      2))
                                          .abs() >
                                      1)
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded,
                                      color: Colors.white70),
                                  tooltip: 'Reset crop',
                                  onPressed: _reset,
                                ),
                              const SizedBox(width: 4),
                              _cropping
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : FilledButton(
                                      onPressed: _done,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 10),
                                      ),
                                      child: const Text(
                                        'Done',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Info Bar
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.crop_square_rounded,
                                    color: accent, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  '1:1 Square (YouTube Music standard)',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
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

/// Custom painter that dims the area outside the square crop frame,
/// draws subtle 3x3 grid lines, and bright corner brackets.
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Color accentColor;

  _CropOverlayPainter({
    required this.cropRect,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(cropRect, const Radius.circular(12));

    // Dim mask outside cropRect
    final maskPath = Path()
      ..addRect(fullRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // Subtle 3x3 rule-of-thirds grid inside crop area
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final thirdW = cropRect.width / 3;
    final thirdH = cropRect.height / 3;

    canvas.drawLine(
      Offset(cropRect.left + thirdW, cropRect.top),
      Offset(cropRect.left + thirdW, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + thirdW * 2, cropRect.top),
      Offset(cropRect.left + thirdW * 2, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdH),
      Offset(cropRect.right, cropRect.top + thirdH),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdH * 2),
      Offset(cropRect.right, cropRect.top + thirdH * 2),
      gridPaint,
    );

    // Border around cropRect
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // Corner bracket accents
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 22.0;

    // Top-left
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cornerLen),
      Offset(cropRect.left, cropRect.top + 6),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + 6, cropRect.top),
      Offset(cropRect.left + cornerLen, cropRect.top),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(cropRect.right - cornerLen, cropRect.top),
      Offset(cropRect.right - 6, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top + 6),
      Offset(cropRect.right, cropRect.top + cornerLen),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom - cornerLen),
      Offset(cropRect.left, cropRect.bottom - 6),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + 6, cropRect.bottom),
      Offset(cropRect.left + cornerLen, cropRect.bottom),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(cropRect.right - cornerLen, cropRect.bottom),
      Offset(cropRect.right - 6, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom - 6),
      Offset(cropRect.right, cropRect.bottom - cornerLen),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.accentColor != accentColor;
  }
}
