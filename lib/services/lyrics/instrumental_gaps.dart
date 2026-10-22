import 'lyrics_models.dart';

/// Shorter instrumental breaks aren't worth interrupting the line for.
const int minGapMs = 4000;

/// Playful phrases displayed during instrumental stretches
class InstrumentalGapTexts {
  static const List<String> introPhrases = [
    'Let it breathe',
    'The beat is landing',
    'The song is starting',
    'Warming up',
    'Setting the mood',
    'Bass first, words later',
    'Wait for it',
    'Feel that build',
    'Just the groove for now',
    'The hook is on the way',
    'Cue the vocals',
    'First notes in',
  ];

  static const List<String> breakPhrases = [
    'Breathing room',
    'Let it breathe',
    'Enjoy the groove',
    'Instrumental break',
    'Solo section',
    'Bass & rhythm',
    'Feel the beat',
    'Just the music',
  ];

  static String getIntroText([int seed = 0]) {
    final index = seed.abs() % introPhrases.length;
    return introPhrases[index];
  }

  static String getBreakText([int seed = 0]) {
    final index = seed.abs() % breakPhrases.length;
    return breakPhrases[index];
  }
}

/// Playful phrases displayed while lyrics are being searched and loaded
class LyricsLoadingTexts {
  static const List<String> phrases = [
    'Finding the words',
    'Finding the right words',
    'Searching the songbook',
    'Checking the lyric sheet',
    'Fetching the verses',
    'Getting the lyrics',
    'Lyrics are loading',
    'Lining up the lyrics',
    'Words are on the way',
    'Checking the archives',
    'Tuning into the vocals',
    'Looking up the lines',
  ];

  static String getText([int seed = 0]) {
    final index = seed.abs() % phrases.length;
    return phrases[index];
  }
}

/// Extension to insert instrumental gaps in lyric lines
extension InstrumentalGapsExtension on List<LyricLine> {
  /// Marks instrumental stretches with gap lines (isGap == true) and playful gap copy.
  ///
  /// A break is only drawn where the line before it says when its singing
  /// stopped (hasKnownEnd). The break appears the moment vocal ends.
  List<LyricLine> withInstrumentalGaps() {
    if (isEmpty) return this;
    final out = <LyricLine>[];

    // If there is a long instrumental intro, insert an intro gap
    if (first.timeInMs >= minGapMs && !first.isGap) {
      final text = InstrumentalGapTexts.getIntroText(first.timeInMs);
      out.add(LyricLine(timeInMs: 0, text: text, isGap: true));
    }

    for (int i = 0; i < length; i++) {
      final line = this[i];
      out.add(line);

      if (i + 1 >= length) break;
      final next = this[i + 1];

      if (line.isGap || next.isGap) continue;

      final int vocalEnd;
      if (line.hasKnownEnd && line.endMs > line.timeInMs) {
        vocalEnd = line.endMs;
      } else {
        // For standard line-synced lyrics (e.g. LRCLib without word-level timing),
        // estimate vocal duration from word count (~300ms/word, bounded 2.5s-4.5s)
        final wordCount = line.text.trim().split(RegExp(r'\s+')).length;
        final estimatedMs = (wordCount * 300).clamp(2500, 4500);
        vocalEnd = line.timeInMs + estimatedMs;
      }

      final silence = next.timeInMs - vocalEnd;
      if (silence >= minGapMs && vocalEnd < next.timeInMs) {
        final text = InstrumentalGapTexts.getBreakText(vocalEnd);
        out.add(LyricLine(timeInMs: vocalEnd, text: text, isGap: true));
      }
    }

    return out;
  }
}
