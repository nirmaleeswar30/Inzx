import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/lyrics/lyrics_models.dart';
import 'package:inzx/services/lyrics/swept_lyric_timing.dart';

void main() {
  LyricLine line(List<(String, int, int)> words) => LyricLine(
    timeInMs: words.first.$2,
    text: words.map((w) => w.$1).join(' '),
    words: [
      for (final (text, start, end) in words)
        LyricWord(text: text, startTimeMs: start, endTimeMs: end),
    ],
  );

  group('SweptTiming.revealedChars', () {
    test('is 0 before the line and the full length after', () {
      final timing = SweptTiming.of(
        line([('hello', 1000, 1500), ('world', 1500, 2000)]),
      );
      expect(timing.revealedChars(0), 0);
      expect(timing.revealedChars(5000), 'hello world'.length);
    });

    test('interpolates across the word being sung', () {
      final timing = SweptTiming.of(line([('hello', 1000, 2000)]));
      // Halfway through a 1000ms word reveals about half its 5 letters.
      expect(timing.revealedChars(1500), closeTo(2.5, 0.01));
    });

    test('a word repeated in the line lines up with its own occurrence', () {
      final timing = SweptTiming.of(
        line([('na', 1000, 1100), ('na', 2000, 2100)]),
      );
      // "na na": the second word's span starts at index 3, not 0.
      expect(timing.wordSpans[1].$1, 3);
      // The first word is fully sung by 1100ms...
      expect(timing.revealedChars(1100), 2);
      // ...then the sweep creeps across the space during the pause, so by
      // 1900ms it is most of the way to the second word but not onto it.
      expect(timing.revealedChars(1900), greaterThan(2));
      expect(timing.revealedChars(1900), lessThan(3));
    });
  });

  group('SweptTiming lift and growth', () {
    test('a quick word barely lifts; a held word lifts fully', () {
      final quick = SweptTiming.of(line([('hi', 1000, 1100)]));
      final held = SweptTiming.of(line([('hiii', 1000, 2000)]));
      final quickPeak = quick.wordLift(0, 1050);
      final heldPeak = held.wordLift(0, 1500);
      expect(quickPeak, lessThan(heldPeak));
      expect(heldPeak, greaterThan(0.6));
    });

    test('only a long-held word is animated letter by letter', () {
      final patter = SweptTiming.of(line([('run', 1000, 1150)]));
      expect(patter.growingWords, isEmpty);
      // "golden" held ~1.6s qualifies.
      final held = SweptTiming.of(line([('golden', 1000, 2600)]));
      expect(held.growingWords, hasLength(1));
      expect(held.growingAt(0), isNotNull);
    });

    test('a held word keeps moving past its end, then rests', () {
      final timing = SweptTiming.of(line([('golden', 1000, 2600)]));
      expect(timing.isGrowing(2600), isTrue);
      final word = timing.growingWords.single;
      expect(word.restsAtMs, greaterThan(word.endMs));
      expect(timing.isLifted(word.restsAtMs - 1), isTrue);
    });

    test('CJK and hyphenated words are left alone', () {
      final cjk = SweptTiming.of(line([('名前', 1000, 3000)]));
      expect(cjk.growingWords, isEmpty);
      final hyphen = SweptTiming.of(line([('well-worn', 1000, 3000)]));
      expect(hyphen.growingWords, isEmpty);
    });
  });
}
