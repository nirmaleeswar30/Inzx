import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/screens/widgets/lyric_clock.dart';

/// Plays [seconds] of 60fps frames against a player at [rate] that reports
/// its position (dated) every 500 ms, and returns how far the words are off.
double _driftAfter(LyricClock clock, {required double rate, int seconds = 10}) {
  var now = 0.0;
  var reportAt = 0.0;
  var report = 0;
  clock.frame(now, 0, 0, 0);
  while (now < seconds * 1000) {
    now += 1000 / 60;
    if (now - reportAt >= 500) {
      reportAt = now;
      report = (now * rate).round();
    }
    clock.frame(now, report, reportAt, 0);
  }
  return clock.displayedMs - now * rate;
}

void main() {
  test('learns a natively changed rate (Automix tempo match)', () {
    expect(_driftAfter(LyricClock(0), rate: 1.17).abs(), lessThan(60));
    expect(_driftAfter(LyricClock(0), rate: 0.86).abs(), lessThan(60));
  });

  test('never runs ahead of a stalled song', () {
    final clock = LyricClock(5000);
    // Buffering: the caller holds on the reading every frame.
    for (var t = 0.0; t < 3000; t += 16) {
      clock.hold(5000, t);
    }
    expect(clock.displayedMs, 5000);
  });

  test('only an announced seek moves the words back', () {
    final clock = LyricClock(0);
    _driftAfter(clock, rate: 1, seconds: 5);
    final before = clock.displayedMs;
    // One stray reading 2 s behind, no seek: held back.
    clock.frame(5016, 3000, 5016, 0);
    expect(clock.displayedMs, greaterThanOrEqualTo(before));
    // A seek to 1 s, announced: taken at once.
    clock.frame(5032, 1000, 5032, 1);
    clock.frame(5300, 1268, 5300, 1);
    expect(clock.displayedMs, closeTo(1268, 40));
  });
}
