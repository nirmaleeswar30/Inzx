import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inzx/core/liquid_glass/liquid_glass_kit.dart';
import 'package:inzx/core/providers/theme_provider.dart';
import 'package:inzx/screens/widgets/progress_bar_painters.dart';
import 'package:inzx/screens/widgets/share_card.dart';
import 'package:inzx/services/share/share_card_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> solidImage(int size, img.ColorRgb8 color) async {
    final source = img.Image(width: size, height: size);
    img.fill(source, color: color);
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(img.encodePng(source)),
    );
    return (await codec.getNextFrame()).image;
  }

  ShareCardData data({
    ui.Image? art,
    ShareCardStyle style = ShareCardStyle.dark,
    ShareCardMode mode = ShareCardMode.song,
    ProgressBarStyle bar = ProgressBarStyle.defaultLinear,
    int theme = 1,
    List<String> lyrics = const [],
  }) => ShareCardData(
    title: 'Song title',
    artist: 'Artist name',
    art: art,
    palette: ShareCardPalette.fromAccent(const Color(0xFFE0245E)),
    style: style,
    mode: mode,
    theme: theme,
    barStyle: bar,
    position: const Duration(seconds: 60),
    duration: const Duration(seconds: 240),
    isPlaying: true,
    seed: 7,
    lyrics: lyrics,
  );

  Future<void> pumpCard(WidgetTester tester, ShareCardData card) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: kShareCardSize),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: ShareCard(data: card)),
        ),
      ),
    );
  }

  group('ShareCard', () {
    testWidgets('lays out without overflow in every style, mode and bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final style in ShareCardStyle.values) {
        for (final bar in ProgressBarStyle.values) {
          await pumpCard(tester, data(style: style, bar: bar));
          expect(tester.takeException(), isNull);
        }
        await pumpCard(
          tester,
          data(
            style: style,
            mode: ShareCardMode.lyrics,
            lyrics: const [
              'A short line',
              'A much longer line that has to wrap onto a second row',
              'Third',
              'Fourth',
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('only Liquid uses the shader glass', (tester) async {
      for (final style in ShareCardStyle.values) {
        await pumpCard(tester, data(style: style));
        expect(
          find.byType(LiquidGlass),
          style == ShareCardStyle.liquid ? findsOneWidget : findsNothing,
        );
      }
    });

    testWidgets('Liquid uses the clear lens with the cover behind the glass', (
      tester,
    ) async {
      final art = await tester.runAsync(
        () => solidImage(8, img.ColorRgb8(0, 200, 0)),
      );
      await pumpCard(tester, data(art: art, style: ShareCardStyle.liquid));
      final glass = find.byType(LiquidGlass);
      final style = tester.widget<LiquidGlass>(glass).style;

      // The edge is the refraction, with the same rim as the app's glass bars.
      expect(style.refractionHeight, greaterThan(0));
      expect(style.refractionAmount, greaterThan(0));
      expect(style.highlight, GlassHighlight.directional);
      expect(style.edgeColor, isNull);

      // Clear glass: anything painted in it would cover the lens.
      expect(style.surfaceColor.a, 0);
      expect(style.blurRadius, 0);
      expect(
        find.descendant(of: glass, matching: find.byType(RawImage)),
        findsNothing,
      );
      expect(find.byType(RawImage), findsWidgets);
    });

    testWidgets('position past the end clamps', (tester) async {
      final card = ShareCardData(
        title: 'T',
        artist: 'A',
        palette: ShareCardPalette.fromAccent(Colors.red),
        style: ShareCardStyle.dark,
        mode: ShareCardMode.song,
        theme: 1,
        barStyle: ProgressBarStyle.defaultLinear,
        position: const Duration(seconds: 500),
        duration: const Duration(seconds: 100),
        isPlaying: false,
        seed: 1,
      );
      expect(card.progress, 1);
    });
  });

  group('CometProgressBarPainter', () {
    test('adding the style leaves saved settings pointing at the same styles', () {
      expect(ProgressBarStyle.values.map((s) => s.name), [
        'defaultLinear',
        'waveform',
        'spectrum',
        'comet',
      ]);
    });

    test('paints from empty to full, in dark and light', () {
      for (final head in [Colors.white, const Color(0xFF111111)]) {
        for (final progress in [0.0, 0.01, 0.5, 1.0]) {
          final recorder = ui.PictureRecorder();
          CometProgressBarPainter(
            progress: progress,
            activeColor: Colors.pink,
            inactiveColor: Colors.grey,
            headColor: head,
            trackHeight: 4,
          ).paint(Canvas(recorder), const Size(300, 38));
          recorder.endRecording().dispose();
        }
      }
    });

    Future<int Function(int x, int y, int channel)> render({
      required double rayOpacity,
    }) async {
      final recorder = ui.PictureRecorder();
      CometProgressBarPainter(
        progress: 0.8,
        activeColor: const Color(0xFFFF0000),
        inactiveColor: const Color(0x00000000),
        headColor: Colors.white,
        trackHeight: 4,
        tailLength: 100,
        rayOpacity: rayOpacity,
      ).paint(Canvas(recorder), const Size(300, 60));
      final image = await recorder.endRecording().toImage(300, 60);
      final bytes = (await image.toByteData())!;
      return (x, y, c) => bytes.getUint8((y * 300 + x) * 4 + c);
    }

    test('the streak brightens from the accent to the head colour', () async {
      final at = await render(rayOpacity: 0);
      expect(at(40, 30, 0), greaterThan(200));
      expect(at(40, 30, 1), lessThan(40));
      expect(at(238, 30, 1), greaterThan(180));
    });

    test('there is no dot or bloom past the end of the streak', () async {
      final at = await render(rayOpacity: 1);
      // The tip is at x=240, on the row through the bar's middle.
      expect(at(246, 30, 3), lessThan(10));
      expect(at(240, 18, 3), lessThan(10));
    });

    test('the ray spreads outward going back from the tip', () async {
      final at = await render(rayOpacity: 1);
      // Well off the bar there's no light beside the tip, but there is
      // further back, where the wedge has opened up.
      expect(at(232, 22, 3), lessThan(at(190, 22, 3)));
      expect(at(190, 22, 3), greaterThan(10));
    });

    test('Comet is what a new install starts on', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ProgressBarStyleNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, ProgressBarStyle.comet);
    });

    test('a style someone already chose is kept', () async {
      SharedPreferences.setMockInitialValues({
        ProgressBarStyleNotifier.progressBarStylePrefKey:
            ProgressBarStyle.waveform.index,
      });
      final notifier = ProgressBarStyleNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, ProgressBarStyle.waveform);
    });

    test('nothing is drawn behind the end of the ray', () async {
      // The blur left a faint vertical line past the point where the ray has
      // faded out. The ray's tail starts at x=140 here.
      final at = await render(rayOpacity: 1);
      for (final y in [12, 18, 22, 25, 35, 38, 42, 48]) {
        for (var x = 100; x < 140; x++) {
          expect(at(x, y, 3), 0, reason: 'x=$x, y=$y');
        }
      }
    });

    test('a paused bar has no ray at all', () async {
      final at = await render(rayOpacity: 0);
      for (final x in [150, 190, 230]) {
        expect(at(x, 22, 3), 0);
        expect(at(x, 38, 3), 0);
      }
    });
  });

  group('ShareCardPalette', () {
    test('a grey cover stays grey', () {
      final palette = ShareCardPalette.fromAccent(const Color(0xFF808080));
      expect(HSLColor.fromColor(palette.tint).saturation, lessThan(0.1));
    });

    test('offers a blurred-cover theme and four gradients', () {
      final palette = ShareCardPalette.fromAccent(Colors.blue);
      expect(palette.backdrop(0), isNull);
      for (var i = 1; i < ShareCardPalette.themeCount; i++) {
        expect(palette.backdrop(i), isNotNull);
      }
    });
  });

  group('ShareCardRenderer', () {
    testWidgets('exports a full-size story image of the card', (tester) async {
      final png = await tester.runAsync(() async {
        final art = await solidImage(64, img.ColorRgb8(0, 200, 0));
        return const ShareCardRenderer().renderPng(
          data(art: art, theme: 1),
          tester.view,
        );
      });
      final image = img.decodePng(png!)!;
      expect(image.width, 1080);
      expect(image.height, 1920);

      // The story's corner is the dark theme background, and the cover shows
      // up green in the card's art, which fills the card's top half.
      final corner = image.getPixel(20, 20);
      expect(corner.g, lessThan(60));
      final artPixel = image.getPixel(540, 700);
      expect(artPixel.g, greaterThan(150));
      expect(artPixel.r, lessThan(60));
    });

    testWidgets('exports the Liquid style too', (tester) async {
      final png = await tester.runAsync(() async {
        final art = await solidImage(64, img.ColorRgb8(0, 200, 0));
        return const ShareCardRenderer().renderPng(
          data(art: art, style: ShareCardStyle.liquid, theme: 0),
          tester.view,
        );
      });
      final image = img.decodePng(png!)!;
      expect(image.width, 1080);
      expect(image.getPixel(540, 700).g, greaterThan(100));
    });

    testWidgets('is solid edge to edge in every style and theme', (
      tester,
    ) async {
      // Anything see-through turns into the viewer's background: dark in a
      // gallery, white once a messaging app flattens it.
      final art = await tester.runAsync(
        () => solidImage(64, img.ColorRgb8(200, 40, 40)),
      );
      for (final style in ShareCardStyle.values) {
        for (var theme = 0; theme < ShareCardPalette.themeCount; theme++) {
          final png = await tester.runAsync(
            () => const ShareCardRenderer().renderPng(
              data(art: art, style: style, theme: theme),
              tester.view,
            ),
          );
          final image = img.decodePng(png!)!;
          final seeThrough = image.where((p) => p.a < 255).length;
          expect(seeThrough, 0, reason: '${style.name}, theme $theme');
        }
      }
    });

    testWidgets('the blurred cover reaches the edges at full strength', (
      tester,
    ) async {
      // No dark layer over the background, and no vignette from the solid
      // colour under it showing through a fading blur.
      final art = await tester.runAsync(
        () => solidImage(64, img.ColorRgb8(0, 200, 0)),
      );
      final png = await tester.runAsync(
        () => const ShareCardRenderer().renderPng(
          data(art: art, theme: 0),
          tester.view,
        ),
      );
      final image = img.decodePng(png!)!;
      for (final (x, y) in [
        (2, 2),
        (1077, 2),
        (2, 1917),
        (1077, 1917),
        (2, 960),
        (1077, 960),
        (540, 2),
        (540, 1917),
      ]) {
        expect(image.getPixel(x, y).g, greaterThan(195), reason: '($x, $y)');
      }
    });

    testWidgets('leaves nothing behind and can run again', (tester) async {
      for (var i = 0; i < 2; i++) {
        final png = await tester.runAsync(
          () => const ShareCardRenderer().renderPng(data(), tester.view),
        );
        expect(png, isNotEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
