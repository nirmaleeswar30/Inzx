import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/l10n/generated/app_localizations.dart';
import 'package:inzx/providers/music_providers.dart';
import 'package:inzx/screens/widgets/lyrics_view.dart';
import 'package:inzx/services/lyrics/lyrics_models.dart';
import 'package:inzx/services/lyrics/lyrics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestLyrics extends LyricsNotifier {
  _TestLyrics(this.lines);

  final List<LyricLine> lines;

  @override
  LyricsState build() {
    return LyricsState(
      providers: {
        ProviderName.lrclib: ProviderStatus(
          state: LyricsProviderState.done,
          data: LyricResult(
            title: 'Song',
            artists: const ['Artist'],
            lines: lines,
            source: 'LRCLIB',
          ),
        ),
      },
    );
  }
}

void main() {
  testWidgets('windowed lyrics find the playhead and release row blur layers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final lines = List.generate(
      90,
      (index) => LyricLine(
        timeInMs: index * 2000,
        text: 'Line $index with enough words to wrap on a narrow panel',
        translatedText: 'A translation that also spans multiple rows of text',
      ),
    );
    final position = ValueNotifier(const Duration(seconds: 108));
    addTearDown(position.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lyricsProvider.overrideWith(() => _TestLyrics(lines)),
          currentTrackProvider.overrideWithValue(null),
          isPlayingProvider.overrideWithValue(false),
          showNerdStatsProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                height: 420,
                child: ValueListenableBuilder<Duration>(
                  valueListenable: position,
                  builder: (_, value, _) =>
                      LyricsView(currentPosition: value, windowedDesktop: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(Viewport));
    final active = find.text(lines[54].text, skipOffstage: false);
    expect(viewport.overlaps(tester.getRect(active)), isTrue);
    final oldLayers = tester.layers.whereType<ImageFilterLayer>().toList();
    expect(oldLayers, isNotEmpty);

    position.value = const Duration(seconds: 114);
    await tester.pumpAndSettle();
    expect(
      viewport.overlaps(tester.getRect(find.text(lines[57].text))),
      isTrue,
    );
    expect(active, findsOneWidget); // Still laid out in the scroll cache.
    expect(viewport.overlaps(tester.getRect(active)), isFalse);
    expect(oldLayers.every((layer) => layer.debugDisposed), isTrue);
    expect(tester.layers.whereType<ImageFilterLayer>(), isNotEmpty);
  });
}
