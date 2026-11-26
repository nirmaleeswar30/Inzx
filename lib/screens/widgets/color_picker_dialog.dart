import '../../core/utils/open_once.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/utils/platform_utils.dart';

/// Glassmorphic modal sheet to pick a custom accent color using a color wheel, sliders, and HEX input.
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  static Future<Color?> show(
    BuildContext context, {
    required Color initialColor,
  }) {
    return openOnce<Color>('ColorPickerDialog', () => showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ColorPickerDialog(
          initialColor: initialColor,
          onColorSelected: (color) => Navigator.pop(context, color),
        ),
      ),
    ));
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _currentHsv;
  late TextEditingController _hexController;
  bool _isHexUpdating = false;

  // Preset palette recommendations
  static const List<Color> _presetColors = [
    Color(0xFF9F7AEA), // Purple / Lilac (Default)
    Color(0xFF6B46C1), // Deep Violet
    Color(0xFF38B2AC), // Teal
    Color(0xFF4299E1), // Sky Blue
    Color(0xFF3182CE), // Royal Blue
    Color(0xFF48BB78), // Emerald Green
    Color(0xFF8FD4B6), // Sage Green
    Color(0xFFECC94B), // Warm Gold
    Color(0xFFED8936), // Vibrant Orange
    Color(0xFFF56565), // Coral Red
    Color(0xFFED64A6), // Bubblegum Pink
    Color(0xFFE53E3E), // Crimson
  ];

  @override
  void initState() {
    super.initState();
    _currentHsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _colorToHex(_currentHsv.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

  void _updateFromHsv(HSVColor hsv) {
    setState(() {
      _currentHsv = hsv;
    });
    if (!_isHexUpdating) {
      _isHexUpdating = true;
      _hexController.text = _colorToHex(hsv.toColor());
      _isHexUpdating = false;
    }
  }

  void _onHexChanged(String value) {
    if (_isHexUpdating) return;
    String cleanHex = value.replaceAll('#', '').trim();
    if (cleanHex.length == 6) {
      final intValue = int.tryParse('FF$cleanHex', radix: 16);
      if (intValue != null) {
        final newColor = Color(intValue);
        setState(() {
          _currentHsv = HSVColor.fromColor(newColor);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentColor = _currentHsv.toColor();
    final sheetBg = isDark
        ? const Color(0xFF141414).withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.92);
    final borderColor = isDark
        ? currentColor.withValues(alpha: 0.28)
        : currentColor.withValues(alpha: 0.20);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = textPrimary.withValues(alpha: 0.55);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            enabled: !isDesktop,
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: modalSheetBackground(context, sheetBg),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: borderColor,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textPrimary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header Title and Preview Swatch
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: currentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: currentColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Iconsax.colorfilter,
                            color: currentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Custom Accent Color',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                'Pick from the wheel or enter a HEX code',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Color Preview Swatch
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: currentColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white30 : Colors.black12,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: currentColor.withValues(alpha: 0.5),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 1. Interactive Color Wheel
                    Center(
                      child: _ColorWheelPicker(
                        hsvColor: _currentHsv,
                        onColorChanged: _updateFromHsv,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Brightness / Value Slider
                    Row(
                      children: [
                        Icon(
                          Iconsax.sun_1,
                          size: 18,
                          color: textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 10,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 9,
                                elevation: 3,
                              ),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              activeTrackColor: currentColor,
                              inactiveTrackColor: currentColor.withValues(alpha: 0.25),
                              thumbColor: currentColor,
                            ),
                            child: Slider(
                              value: _currentHsv.value,
                              min: 0.1,
                              max: 1.0,
                              onChanged: (val) {
                                _updateFromHsv(_currentHsv.withValue(val));
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 3. HEX Input and Presets Row
                    Row(
                      children: [
                        // Glass HEX input container
                        Container(
                          width: 135,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '#',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: currentColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: _hexController,
                                  maxLength: 6,
                                  textCapitalization: TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                                  ],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    counterText: '',
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onChanged: _onHexChanged,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Preset Swatches Horizontal Scroll
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _presetColors.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final preset = _presetColors[index];
                                final isSelected = currentColor.toARGB32() == preset.toARGB32();
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _updateFromHsv(HSVColor.fromColor(preset));
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: preset,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.white
                                            : (isDark ? Colors.white12 : Colors.black12),
                                        width: isSelected ? 2.5 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: preset.withValues(alpha: 0.6),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check,
                                            size: 18,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              widget.onColorSelected(currentColor);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentColor,
                              foregroundColor: currentColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Apply Accent Color',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom HSV Color Wheel Painter & Gesture Detector
class _ColorWheelPicker extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onColorChanged;
  static const double size = 200;

  const _ColorWheelPicker({
    required this.hsvColor,
    required this.onColorChanged,
  });

  void _handleTouch(Offset localPosition) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final maxRadius = size / 2;

    // Angle calculation for Hue [0..360]
    var angle = math.atan2(dy, dx) * 180 / math.pi;
    if (angle < 0) angle += 360;

    // Distance calculation for Saturation [0..1]
    final saturation = (distance / maxRadius).clamp(0.0, 1.0);

    onColorChanged(
      HSVColor.fromAHSV(
        1.0,
        angle,
        saturation,
        hsvColor.value.clamp(0.1, 1.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _handleTouch(details.localPosition),
      onPanUpdate: (details) => _handleTouch(details.localPosition),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _ColorWheelPainter(
            hsvColor: hsvColor,
          ),
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final HSVColor hsvColor;

  _ColorWheelPainter({required this.hsvColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Draw Hue sweep gradient
    final sweepGradient = SweepGradient(
      colors: const [
        Color(0xFFFF0000), // Red
        Color(0xFFFFFF00), // Yellow
        Color(0xFF00FF00), // Green
        Color(0xFF00FFFF), // Cyan
        Color(0xFF0000FF), // Blue
        Color(0xFFFF00FF), // Magenta
        Color(0xFFFF0000), // Red
      ],
      stops: const [0.0, 0.166, 0.333, 0.5, 0.666, 0.833, 1.0],
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // 2. Draw Saturation radial gradient (white center to transparent edge)
    final radialGradient = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: hsvColor.value),
        Colors.transparent,
      ],
      stops: const [0.0, 1.0],
    );

    final radialPaint = Paint()
      ..shader = radialGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, radialPaint);

    // 3. Draw Thumb Indicator
    final angleRad = hsvColor.hue * math.pi / 180;
    final dist = hsvColor.saturation * radius;
    final thumbX = center.dx + dist * math.cos(angleRad);
    final thumbY = center.dy + dist * math.sin(angleRad);

    final thumbCenter = Offset(thumbX, thumbY);

    // Thumb shadow
    canvas.drawCircle(
      thumbCenter,
      12,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Thumb outer ring
    canvas.drawCircle(
      thumbCenter,
      11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Thumb inner color swatch
    canvas.drawCircle(
      thumbCenter,
      8,
      Paint()
        ..color = hsvColor.toColor()
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor;
  }
}
