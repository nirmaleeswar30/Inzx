import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../screens/widgets/share_card.dart';

/// Paints a [ShareCard] to a 1080x1920 PNG, away from the screen.
///
/// The card gets a small render tree of its own whose view is exactly the
/// image. Besides being independent of what's on screen, that is what lets the
/// glass work: its lens is told where the card is in "physical pixels from the
/// top-left of the view", and here those are the image's own pixels. Capturing
/// the preview instead would hand the lens its on-screen position, which means
/// nothing in the image, and bend the wrong part of the backdrop.
class ShareCardRenderer {
  const ShareCardRenderer();

  static const double _pixelRatio = 3;

  Future<Uint8List> renderPng(ShareCardData data, ui.FlutterView view) async {
    final size = kShareCardSize;
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size * _pixelRatio),
        devicePixelRatio: _pixelRatio,
      ),
      child: RenderPositionedBox(child: boundary),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final focusManager = FocusManager();
    final buildOwner = BuildOwner(focusManager: focusManager);
    RenderObjectToWidgetAdapter<RenderBox> tree(Widget child) => RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: _pixelRatio),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );

    final root = tree(ShareCard(data: data)).attachToRenderTree(buildOwner);
    try {
      buildOwner
        ..buildScope(root)
        ..finalizeTree();
      pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();

      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Card could not be encoded');
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      // Swapping the card out disposes its render objects and glass shaders.
      buildOwner
        ..buildScope(root, () {
          root.update(tree(const SizedBox.shrink()));
        })
        ..finalizeTree();
      focusManager.dispose();
    }
  }

  /// Renders the card into the folder `ShareBridge.kt` is allowed to hand out.
  Future<File> renderToFile(
    ShareCardData data,
    ui.FlutterView view, {
    required String name,
  }) async {
    final png = await renderPng(data, view);
    final dir = Directory('${(await getTemporaryDirectory()).path}/share_cards');
    if (await dir.exists()) {
      // Only the latest card is ever needed again.
      await for (final old in dir.list()) {
        try {
          await old.delete();
        } catch (e) {
          debugPrint('ShareCardRenderer: could not clear $old: $e');
        }
      }
    } else {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(png, flush: true);
    return file;
  }
}
