import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Loads the two glass fragment programs once for the whole app.
///
/// Call [ensureLoaded] before `runApp`. Until it completes, or when the
/// renderer cannot run a shader as an image filter (the Skia backend),
/// glass falls back to colour controls, blur, tint, rim and shadow with no
/// lens — the same step down the Kotlin version takes on Android 12, where
/// RenderEffect exists but RuntimeShader does not.
abstract final class GlassShaders {
  static ui.FragmentProgram? _lens;
  static ui.FragmentProgram? _highlight;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _lens = await ui.FragmentProgram.fromAsset('shaders/glass_lens.frag');
    } catch (e) {
      debugPrint('liquid glass: lens shader unavailable ($e)');
    }
    try {
      _highlight =
          await ui.FragmentProgram.fromAsset('shaders/glass_highlight.frag');
    } catch (e) {
      debugPrint('liquid glass: highlight shader unavailable ($e)');
    }
  }

  /// Whether the refraction lens can run on this renderer.
  static bool get lensSupported =>
      _lens != null && ui.ImageFilter.isShaderFilterSupported;

  static ui.FragmentShader? createLens() =>
      lensSupported ? _lens!.fragmentShader() : null;

  static ui.FragmentShader? createHighlight() => _highlight?.fragmentShader();
}
