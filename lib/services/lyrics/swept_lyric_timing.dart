// Ported from BitChord's LyricLine / GrowingWord timing (GPL-3.0); see
// BITCHORD_LICENSE.txt.

import 'dart:math' as math;

import 'lyrics_models.dart';

/// The timing behind a word-synced line as BitChord draws it: how far the
/// sweep has got, how high each word has lifted, and the held words that are
/// animated letter by letter. Built once per line (see [SweptTiming.of]) and
/// read on every frame the line moves.
class SweptTiming {
  SweptTiming._(LyricLine line)
    : text = line.text,
      timeMs = line.timeInMs,
      words = line.words ?? const [] {
    var offset = 0;
    final spans = <(int, int)>[];
    for (final word in words) {
      final found = text.indexOf(word.text, offset);
      final start = found >= 0 ? found : offset;
      final end = start + word.text.length;
      offset = end;
      spans.add((start, end));
    }
    wordSpans = spans;
    final lead = words.isNotEmpty
        ? words.last.endTimeMs
        : (line.sungUntilMs ?? line.timeInMs);
    var end = lead;
    for (final backing in line.backgroundLines) {
      final backingWords = backing.words;
      final backingEnd = backingWords != null && backingWords.isNotEmpty
          ? backingWords.last.endTimeMs
          : (backing.sungUntilMs ?? backing.timeInMs);
      end = math.max(end, backingEnd);
    }
    endMs = end;
    growingWords = [
      for (var i = 0; i < words.length; i++)
        if (_canGrow(words[i])) GrowingWord._(i, words[i]),
    ];
    animatesFromMs = math.min(
      timeMs,
      words.isNotEmpty ? words.first.startTimeMs : timeMs,
    );
    final settled = words.isNotEmpty
        ? words.last.endTimeMs + _riseMs.toInt()
        : endMs;
    var grown = -1 << 52;
    for (final word in growingWords) {
      grown = math.max(grown, word.restsAtMs);
    }
    animatesUntilMs = math.max(endMs, math.max(settled, grown));
  }

  static final Expando<SweptTiming> _cache = Expando('sweptTiming');

  /// The timing for [line], worked out the first time it is asked for.
  static SweptTiming of(LyricLine line) =>
      _cache[line] ??= SweptTiming._(line);

  final String text;
  final int timeMs;
  final List<LyricWord> words;

  /// Where each of [words] sits in [text], as `[start, end)` character
  /// ranges. Walked from where the last one ended rather than searched from
  /// the start, so a word repeated in the line lines up with its own
  /// occurrence.
  late final List<(int, int)> wordSpans;

  /// When the last word (or the answering vocal) finishes.
  late final int endMs;

  /// The words held long enough to be worth animating letter by letter.
  late final List<GrowingWord> growingWords;

  /// The stretch over which anything drawn for this line moves. Before it the
  /// line is drawn unsung, after it sung and at rest, and either way exactly
  /// the same on every frame.
  late final int animatesFromMs;
  late final int animatesUntilMs;

  bool get isWordSynced => words.isNotEmpty;

  /// How far through the line the singing has got, as a fractional index into
  /// [text]. Within a word it interpolates across that word's own span, so a
  /// held note draws slowly and a rattled-off one snaps. Whitespace between two
  /// words fills over the pause between them.
  double revealedChars(int positionMs) {
    if (words.isEmpty) {
      return positionMs >= timeMs ? text.length.toDouble() : 0;
    }
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final (start, end) = wordSpans[index];
      if (positionMs < word.startTimeMs) return start.toDouble();
      if (positionMs < word.endTimeMs) {
        return start + _charsSungAt(word, positionMs);
      }
      if (index + 1 < words.length) {
        final next = words[index + 1];
        if (positionMs < next.startTimeMs) {
          final gapStart = wordSpans[index + 1].$1;
          final pause = math.max(1, next.startTimeMs - word.endTimeMs);
          final through = (positionMs - word.endTimeMs) / pause;
          return end + through * (gapStart - end);
        }
      }
    }
    return text.length.toDouble();
  }

  static double _charsSungAt(LyricWord word, int positionMs) {
    if (positionMs <= word.startTimeMs) return 0;
    if (positionMs >= word.endTimeMs) return word.text.length.toDouble();
    final span = math.max(1, word.endTimeMs - word.startTimeMs);
    return (positionMs - word.startTimeMs) / span * word.text.length;
  }

  /// Whether anything on this line is off the floor at [positionMs].
  bool isLifted(int positionMs) {
    if (words.isEmpty) return false;
    if (positionMs <= words.first.startTimeMs) return false;
    return positionMs < words.last.endTimeMs + _riseMs || isGrowing(positionMs);
  }

  /// How far the word [index] has lifted, 0..1: it rises over its own length
  /// (bounded) as it is sung and settles back over [_riseMs] from its end.
  /// How high it goes is set by how long it is held.
  double wordLift(int index, int positionMs) {
    if (index < 0 || index >= words.length) return 0;
    final word = words[index];
    final riseMs = (word.endTimeMs - word.startTimeMs).toDouble().clamp(
      _riseMinMs,
      _riseMs,
    );
    final rising = ((positionMs - word.startTimeMs) / riseMs).clamp(0.0, 1.0);
    final falling = (1 - (positionMs - word.endTimeMs) / _riseMs).clamp(
      0.0,
      1.0,
    );
    return _liftHeight(word) * _smooth(math.min(rising, falling));
  }

  /// How much of a word's lift is left at [positionMs]: its full height while
  /// sung, easing to 0 over [_riseMs] once past. The half of the movement a
  /// letter-by-letter word shares with every other word.
  double wordFall(int index, int positionMs) {
    if (index < 0 || index >= words.length) return 0;
    final word = words[index];
    final falling = (1 - (positionMs - word.endTimeMs) / _riseMs).clamp(
      0.0,
      1.0,
    );
    return _liftHeight(word) * _smooth(falling);
  }

  /// The letter-by-letter treatment for word [index], where it has earned one.
  GrowingWord? growingAt(int index) {
    for (final word in growingWords) {
      if (word.index == index) return word;
    }
    return null;
  }

  /// Whether any word on this line is mid-flight at [positionMs].
  bool isGrowing(int positionMs) => growingWords.any(
    (word) => positionMs >= word.startMs && positionMs <= word.restsAtMs,
  );
}

/// One word held long enough to be animated a letter at a time. Every letter
/// runs the same three-beat move — swell up and forward, hold, then settle
/// back to the small lift every sung word carries — each starting
/// [_growStagger] of the word's length after the one before, so the movement
/// travels along the word.
class GrowingWord {
  GrowingWord._(this.index, LyricWord word)
    : startMs = word.startTimeMs,
      endMs = word.endTimeMs,
      _chars = word.text.length {
    _scalePeak = List.filled(_chars, 0);
    _shiftPeak = List.filled(_chars, 0);
    _risePeak = List.filled(_chars, 0);
    _bloomPeak = List.filled(_chars, 0);
    final held = math.max(1, endMs - startMs).toDouble();
    var earned = ((held - _growRampMinMs) / (_growRampMaxMs - _growRampMinMs))
        .clamp(0.0, 1.0);
    earned = earned * earned * earned;
    final decay = _decayRate(_chars, held);
    final bloomPace = math.min(_growBloomPaceMax, held / _growBloomPaceMs);
    final bloomSpread = _chars <= 3
        ? _growBloomShort
        : _chars >= 6
        ? _growBloomLong
        : 1.0;
    final base = _chars <= 3 ? _growBaseShort : _growBaseLong;
    final liftPace = (held / _growLiftPaceMs).clamp(_growLiftFloor, 1.0);

    for (var i = 0; i < _chars; i++) {
      final place = _chars > 1 ? i / (_chars - 1) : 0.0;
      final reach = earned * (1 - place * decay);
      final scale = 1 + base + reach * _growScaleRange;
      _scalePeak[i] = scale * _growScaleTrim;
      _bloomPeak[i] =
          (_growBloomFloor + reach * _growBloomRange) * bloomPace * bloomSpread;
      _risePeak[i] = ((scale - 1) / _growScaleCeiling) * liftPace;
      final centre = (i + 0.5) / _chars;
      _shiftPeak[i] =
          (centre - 0.5) * 2 * (scale - 1) * _growShiftEm * _growScaleTrim;
    }

    final last = math.max(0, _chars - 1) * _growStagger + _growSpan;
    restsAtMs = startMs + (held * last).toInt();
  }

  /// Which of the line's words this is.
  final int index;
  final int startMs;
  final int endMs;
  final int _chars;
  late final List<double> _scalePeak;
  late final List<double> _shiftPeak;
  late final List<double> _risePeak;
  late final List<double> _bloomPeak;

  /// When the last letter has finished moving and is just sitting lifted.
  late final int restsAtMs;

  /// Where letter [charIndex] has got to at [positionMs], written into [into].
  /// [CharGrowth.rise] is in multiples of the ordinary sung-word lift and
  /// [CharGrowth.shift] in ems.
  void sampleInto(int charIndex, int positionMs, CharGrowth into) {
    if (charIndex < 0 || charIndex >= _chars) {
      into
        ..scale = 1
        ..shift = 0
        ..rise = _growRest
        ..bloom = 0;
      return;
    }
    final span = math.max(1, endMs - startMs).toDouble();
    final elapsed = positionMs - startMs - charIndex * span * _growStagger;
    final phase = (elapsed / (span * _growSpan)).clamp(0.0, 1.0);
    final peakScale = _scalePeak[charIndex];
    if (phase < _growIn) {
      final t = _smooth(phase / _growIn);
      into
        ..scale = 1 + (peakScale - 1) * t
        ..shift = _shiftPeak[charIndex] * t
        ..rise = _risePeak[charIndex] * t
        ..bloom = _bloomPeak[charIndex] * t;
    } else if (phase < _growHold) {
      into
        ..scale = peakScale
        ..shift = _shiftPeak[charIndex]
        ..rise = _risePeak[charIndex]
        ..bloom = _bloomPeak[charIndex];
    } else if (phase < _growOut) {
      final t = _smooth((phase - _growHold) / (_growOut - _growHold));
      into
        ..scale = peakScale + (1 - peakScale) * t
        ..shift = _shiftPeak[charIndex] * (1 - t)
        ..rise = _risePeak[charIndex] + (_growRest - _risePeak[charIndex]) * t
        ..bloom = _bloomPeak[charIndex] * (1 - t);
    } else {
      into
        ..scale = 1
        ..shift = 0
        ..rise = _growRest
        ..bloom = 0;
    }
  }
}

/// Where one letter of a [GrowingWord] is, filled in by
/// [GrowingWord.sampleInto].
class CharGrowth {
  /// Swell, about the letter's own centre. 1 is the letter as laid out.
  double scale = 1;

  /// Lean away from the middle of the word, in ems.
  double shift = 0;

  /// Lift, in multiples of the ordinary sung-word rise.
  double rise = 0;

  /// Bloom, 0..1.
  double bloom = 0;
}

/// How long a word takes to rise, and to settle back down once it is past.
const double _riseMs = 700;

/// The quickest a word ever rises: a 90 ms syllable snapping up reads as a
/// twitch.
const double _riseMinMs = 250;

/// How far up a word goes, as a share of the full lift, from how long it is
/// held: patter barely leaves the line, a carried note goes all the way up.
double _liftHeight(LyricWord word) {
  final held = (word.endTimeMs - word.startTimeMs).toDouble();
  final through = ((held - _liftQuickMs) / (_liftHeldMs - _liftQuickMs)).clamp(
    0.0,
    1.0,
  );
  return _liftFloor + (1 - _liftFloor) * _smooth(through);
}

const double _liftQuickMs = 150;
const double _liftHeldMs = 900;
const double _liftFloor = 0.25;

/// Ease in and out of the ends, so the lift has no corners on it.
double _smooth(double fraction) => fraction * fraction * (3 - 2 * fraction);

/// Whether this word is held long enough, and is short enough, to be animated
/// a letter at a time. Block scripts (Han, kana, Hangul) and joined scripts
/// are left alone, as is a hyphenated word.
bool _canGrow(LyricWord word) {
  final text = word.text;
  final length = text.length;
  if (length == 0 || length > _growMaxChars) return false;
  if (text.contains('-')) return false;
  for (final unit in text.codeUnits) {
    if (_isBlockScript(unit) || _isJoinedScript(unit)) return false;
  }
  final held = word.endTimeMs - word.startTimeMs;
  if (length == 1) return held >= _growMinSoloMs;
  if (length <= 3) {
    return held >= _growMinShortMs + (length - 2) * _growShortStepMs;
  }
  if (length == 4) return held >= _growMinFourMs;
  return held >= _growMinLongMs && held >= length * _growMsPerChar;
}

/// How much of the movement is taken back off the later letters of a word.
double _decayRate(int length, double heldMs) {
  final long = length > _growDecayLongChars;
  final quick = heldMs < _growDecayQuickMs;
  if (!long && !quick) return 0;
  var strength = 0.0;
  if (long) {
    strength +=
        math.min((length - _growDecayLongChars) / 5, 1.0) * _growDecayLong;
  }
  if (quick) {
    final short = math.max(0.0, 1 - (heldMs - _growDecayQuickFloorMs) / 400);
    strength += short * (length > 3 ? _growDecayQuick : _growDecayQuickTiny);
  }
  return math.min(strength, _growDecayMax);
}

bool _isBlockScript(int c) =>
    (c >= 0x4E00 && c <= 0x9FFF) ||
    (c >= 0x3040 && c <= 0x309F) ||
    (c >= 0x30A0 && c <= 0x30FF) ||
    (c >= 0xAC00 && c <= 0xD7AF);

bool _isJoinedScript(int c) => c >= 0x0590 && c <= 0x08FF;

const int _growMaxChars = 7;
const int _growMinSoloMs = 1100;
const int _growMinShortMs = 1360;
const int _growShortStepMs = 140;
const int _growMinFourMs = 1050;
const int _growMinLongMs = 900;
const int _growMsPerChar = 200;

const int _growDecayLongChars = 5;
const double _growDecayQuickMs = 1200;
const double _growDecayQuickFloorMs = 800;
const double _growDecayLong = 0.4;
const double _growDecayQuick = 0.3;
const double _growDecayQuickTiny = 0.1;
const double _growDecayMax = 0.7;

/// Each letter starts this far — as a share of the word's own length — after
/// the one before it.
const double _growStagger = 0.09;

/// The whole move runs half again as long as the word is held.
const double _growSpan = 1.5;

/// Up by [_growIn], held to [_growHold], settled by [_growOut].
const double _growIn = 0.25;
const double _growHold = 0.30;
const double _growOut = 0.75;

/// Where a letter comes to rest: the same small lift every sung word carries.
const double _growRest = 1;

const double _growRampMinMs = 400;
const double _growRampMaxMs = 3000;
const double _growBaseShort = 0.05;
const double _growBaseLong = 0.04;
const double _growScaleRange = 0.08;
const double _growScaleCeiling = 0.1;
const double _growScaleTrim = 0.98;
const double _growShiftEm = 25 / 34;
const double _growBloomFloor = 0.35;
const double _growBloomRange = 0.45;
const double _growBloomPaceMs = 1500;
const double _growBloomPaceMax = 1.1;
const double _growBloomShort = 0.85;
const double _growBloomLong = 1.1;
const double _growLiftPaceMs = 2000;
const double _growLiftFloor = 0.3;
