/// The rungs Auto moves between, worst first.
enum QualityStep { opus, jioSaavn, flac }

/// The rules behind Auto quality: when the network is struggling, how far to
/// step down, and when FLAC gets another try.
///
/// Auto starts on FLAC on any connection and only reacts to how playback is
/// actually going. A long stall, a second stall within a minute, or a buffer
/// draining towards empty steps it down a rung. After a wait it tries going
/// back up; that try loads silently and only switches once it's ready, so a
/// failed try costs nothing audible. Each failure, or a stall soon after going
/// back up, doubles the wait, so it can't bounce between qualities.
///
/// Plain logic with the clock passed in, so the timing can be tested without a
/// player. The player owns the actual swaps.
class AutoQuality {
  static const firstWait = Duration(minutes: 3);
  static const longestWait = Duration(minutes: 12);

  /// A single stall this long steps down on its own.
  static const longStall = Duration(seconds: 3);

  /// Anything shorter is a blip and doesn't count as a stall at all.
  static const countedStall = Duration(milliseconds: 500);

  /// Two counted stalls this close together step down.
  static const stallWindow = Duration(minutes: 1);

  /// After going back up, a stall this soon means the connection hadn't
  /// really recovered, so the next wait doubles.
  static const probation = Duration(seconds: 90);

  // Draining: less than [_lowBuffer] left, and it fell by at least [_drain]
  // across the samples kept, measured over at least [_minTrend].
  static const _lowBuffer = Duration(seconds: 8);
  static const _drain = Duration(seconds: 4);
  static const _minTrend = Duration(seconds: 6);
  static const _trendWindow = Duration(seconds: 10);

  /// The best rung the next song may start on.
  QualityStep level = QualityStep.flac;

  /// When the next try to go back up is due; null at the top.
  DateTime? retryAt;

  Duration _wait = firstWait;
  DateTime? _probationEnds;
  DateTime? _stallStart;
  final List<DateTime> _recentStalls = [];
  final List<({DateTime at, Duration ahead})> _bufferSamples = [];

  bool get isLowered => level != QualityStep.flac;

  bool _retryDue(DateTime now) => retryAt != null && !now.isBefore(retryAt!);

  /// Whether a new song may start straight on FLAC. Not during a retry: that
  /// has to be the silent kind, not a song that stalls if it's wrong.
  bool get startsOnFlac => level == QualityStep.flac;

  /// Whether a playing song may try moving onto FLAC.
  bool allowsFlacUpgrade(DateTime now) => !isLowered || _retryDue(now);

  bool allowsJioSaavn(DateTime now) =>
      level != QualityStep.opus || _retryDue(now);

  void stallStarted(DateTime now) => _stallStart ??= now;

  void stallEnded(DateTime now) {
    final start = _stallStart;
    _stallStart = null;
    if (start != null && now.difference(start) >= countedStall) {
      _recentStalls.add(now);
    }
  }

  /// Whether the stall in progress is reason enough to step down.
  bool shouldDrop(DateTime now) {
    _recentStalls.removeWhere((at) => now.difference(at) > stallWindow);
    final start = _stallStart;
    if (start == null) return false;
    final stalled = now.difference(start);
    return stalled >= longStall ||
        (stalled >= countedStall && _recentStalls.isNotEmpty);
  }

  /// Records how much audio is buffered ahead of the playhead. True when it's
  /// low and draining, so the switch can happen before the stall is heard.
  bool noteBuffer(DateTime now, Duration ahead) {
    _bufferSamples.add((at: now, ahead: ahead));
    _bufferSamples.removeWhere((s) => now.difference(s.at) > _trendWindow);
    if (ahead > _lowBuffer) return false;
    final oldest = _bufferSamples.first;
    return now.difference(oldest.at) >= _minTrend &&
        oldest.ahead - ahead >= _drain;
  }

  /// A seek or a new source: the buffer's trend so far means nothing.
  void forgetBufferTrend() => _bufferSamples.clear();

  /// Playback moved down to [step] (or, at [QualityStep.opus] with nothing
  /// lower, stayed there and stalled again, which restarts the wait).
  void lowered(DateTime now, QualityStep step) {
    final onProbation =
        _probationEnds != null && now.isBefore(_probationEnds!);
    if (onProbation) {
      _doubleWait();
    } else if (!isLowered) {
      _wait = firstWait;
    }
    _probationEnds = null;
    level = step;
    retryAt = now.add(_wait);
    _forgetStalls();
  }

  /// A try at going back up landed on [step]. It's kept, on probation.
  void tryLanded(DateTime now, QualityStep step) {
    if (step.index > level.index) level = step;
    if (!isLowered) retryAt = null;
    _probationEnds = now.add(probation);
    _forgetStalls();
  }

  /// A try at going back up couldn't get ready in time.
  void tryFailed(DateTime now) {
    _doubleWait();
    retryAt = now.add(_wait);
  }

  /// A different network is a fresh start: true when a try is worth making
  /// right away.
  bool networkChanged(DateTime now) {
    _forgetStalls();
    if (!isLowered) return false;
    _wait = firstWait;
    retryAt = now;
    return true;
  }

  /// Back to the top, as when the quality setting changes.
  void reset() {
    level = QualityStep.flac;
    retryAt = null;
    _wait = firstWait;
    _probationEnds = null;
    _forgetStalls();
  }

  void _doubleWait() {
    final doubled = _wait * 2;
    _wait = doubled > longestWait ? longestWait : doubled;
  }

  void _forgetStalls() {
    _stallStart = null;
    _recentStalls.clear();
    _bufferSamples.clear();
  }
}
