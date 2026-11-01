// Ported from BitChord's LyricClock (GPL-3.0); see BITCHORD_LICENSE.txt.

/// The lyric playhead: a clock that runs on its own frames and is *steered*
/// by the player's readings rather than set by them.
///
/// Three rules, each the answer to a way this has gone wrong before:
///
///  1. **A reading is dated by when it was taken, not when it was seen.** The
///     native player's reading waits on the platform channel and then on the
///     UI thread; dated on arrival, a reading from before a stall looks
///     fresh. Every reading carries its own stamp and is compared with where
///     the song was *at that moment*.
///  2. **Nothing but an announced jump moves the words backwards.** The player
///     says when it seeks (the `discontinuity` handed to [frame]); that, and
///     only that, may roll the words back. A reading that disagrees without
///     one is held back until the next confirms it, and a confirmed gap
///     behind the words is absorbed by running slower — never by stopping and
///     never by reversing.
///  3. **Readings steer, they don't set.** The newest reading, carried forward
///     at the learned playback rate, is where the song is; the words close
///     the gap to it by running up to [_maxSlew] faster or [_maxSlow] slower.
///     The rate is learned from the readings themselves, which is how Automix
///     tempo matching stays in step without being told.
///
/// All times are milliseconds on one wall clock. Plain arithmetic with no
/// Flutter in it, so it can be tested frame by frame.
class LyricClock {
  LyricClock(int startMs) : displayedMs = startMs.toDouble();

  /// Where the lyrics are drawn, in song milliseconds.
  double displayedMs;

  double _lastNowMs = double.nan;

  // The newest reading seen, to tell a new one from the same one again.
  int? _lastReportMs;
  double _lastSampledAtMs = double.nan;

  /// When playback was last seen stopped; a reading taken before then was
  /// taken standing still.
  double _heldAtMs = double.negativeInfinity;

  int? _lastDiscontinuity;
  bool _jumpPending = false;

  // The newest reading believed: where the song was, and when.
  double _anchorAtMs = double.nan;
  double _anchorMs = 0;

  /// The playback rate, learned from how far the song moves between readings.
  double _rate = 1;

  // Readings believed since the playhead last jumped, oldest first: what the
  // rate is measured across. See [_learnRate].
  final List<double> _historyAt = List.filled(_history, 0);
  final List<double> _historyMs = List.filled(_history, 0);
  int _historySize = 0;

  /// Whether the rate has been measured across a long enough stretch.
  bool _rateSettled = false;

  // A reading that disagreed with the anchor, kept until the next one says
  // whether the song really moved or the reading was wrong.
  double _suspectAtMs = double.nan;
  int _suspectMs = 0;
  int _rejections = 0;

  double _glideStartMs = double.nan;
  double _glideOffsetMs = 0;

  /// Forget the run so far: frames stopped arriving — playback paused, or the
  /// lyrics left the screen — and the next [frame] starts a new one.
  void restart() {
    _lastNowMs = double.nan;
    _jumpPending = false;
    _glideStartMs = double.nan;
    _clearSuspect();
  }

  /// Playback is not moving: settle on [positionMs] outright, as of [nowMs].
  /// Called again for every frame while stopped, which is how a seek made
  /// while paused still moves the words.
  void hold(int positionMs, double nowMs) {
    restart();
    displayedMs = positionMs.toDouble();
    _heldAtMs = nowMs;
  }

  /// Advance to the frame at [nowMs] and return where the lyrics should be
  /// drawn.
  ///
  /// [reportedMs] is the player's latest reading and [sampledAtMs] when it
  /// was taken. [discontinuity] is any value that changes when the playhead
  /// jumps on purpose; only its changing matters.
  int frame(double nowMs, int reportedMs, double sampledAtMs, int discontinuity) {
    final firstOfRun = _lastNowMs.isNaN;
    if (discontinuity != _lastDiscontinuity) {
      if (_lastDiscontinuity != null && !firstOfRun) _jumpPending = true;
      _lastDiscontinuity = discontinuity;
    }
    final isNew = reportedMs != _lastReportMs ||
        (!sampledAtMs.isNaN && sampledAtMs != _lastSampledAtMs);
    _lastReportMs = reportedMs;
    _lastSampledAtMs = sampledAtMs;

    if (firstOfRun) {
      _lastNowMs = nowMs;
      // Taken while playback stood still — the last reading before a pause,
      // or one made during it — it is where the song still is now, however
      // long ago it was taken. Taken while playing, the song has moved on
      // since by exactly how long ago that was.
      final takenAt = sampledAtMs.isNaN || sampledAtMs <= _heldAtMs
          ? nowMs
          : (sampledAtMs < nowMs ? sampledAtMs : nowMs);
      _anchor(takenAt, reportedMs);
      displayedMs = _targetAt(nowMs);
      return displayedMs.toInt();
    }

    // Carried up to this frame on what was known before it, and only then
    // corrected by anything new: a jump folded in first would be advanced by
    // this frame a second time.
    final dt = (nowMs - _lastNowMs).clamp(0.0, double.infinity);
    _lastNowMs = nowMs;
    _advance(nowMs, dt);

    if (isNew) {
      // A stamp from the future is a frame clock running a hair behind the
      // reading; one from before the anchor is out of order, and says nothing
      // the anchor does not.
      final takenAt = sampledAtMs.isNaN
          ? nowMs
          : (sampledAtMs < nowMs ? sampledAtMs : nowMs);
      if (takenAt >= _anchorAtMs || _jumpPending) _take(nowMs, takenAt, reportedMs);
    }
    return displayedMs.toInt();
  }

  /// Folds one new reading in — or holds it back, if it disagrees with the
  /// song so far.
  void _take(double nowMs, double takenAt, int reportedMs) {
    if (_jumpPending) {
      // The reading the jump was announced with: where the song landed.
      _jumpPending = false;
      _clearSuspect();
      _anchor(takenAt, reportedMs);
      _jumpTo(nowMs);
      return;
    }
    final elapsed = takenAt - _anchorAtMs;
    if ((reportedMs - (_anchorMs + elapsed * _rate)).abs() <= _tolerance(elapsed)) {
      _clearSuspect();
      _anchor(takenAt, reportedMs, continues: true);
      return;
    }
    // Off with nothing announced. One reading like that is a bad reading; a
    // second agreeing with it is the song somewhere else. And a run of them,
    // however they disagree, means the picture so far is what is wrong.
    final sinceSuspect = takenAt - _suspectAtMs;
    final agrees = !_suspectAtMs.isNaN &&
        sinceSuspect >= 0 &&
        (reportedMs - (_suspectMs + sinceSuspect * _rate)).abs() <=
            _tolerance(sinceSuspect);
    _rejections++;
    if (agrees) {
      // The two agree with each other, so between them they are the start of
      // the song's new stretch — and its first rate measurement.
      final firstAt = _suspectAtMs;
      final first = _suspectMs;
      _clearSuspect();
      _anchor(firstAt, first);
      _anchor(takenAt, reportedMs, continues: true);
    } else if (_rejections > _maxRejections) {
      _clearSuspect();
      _anchor(takenAt, reportedMs);
      // From here [_advance] closes the gap: ahead of the words it glides
      // forward; behind them it slows down — still never backwards.
    } else {
      _suspectAtMs = takenAt;
      _suspectMs = reportedMs;
    }
  }

  /// How far a reading [elapsedMs] after the last may stray before it is
  /// doubted: a fixed allowance for the player's own noise, and a little more
  /// the longer the gap, for a rate not yet learned exactly.
  double _tolerance(double elapsedMs) =>
      _outlierMs + elapsedMs.abs() * (_rateSettled ? _rateSlack : _unsettledRateSlack);

  /// Believes a reading. [continues] says it carries on from the one before —
  /// the song has not jumped between them — so the two can measure the rate.
  void _anchor(double atMs, int positionMs, {bool continues = false}) {
    _anchorAtMs = atMs;
    _anchorMs = positionMs.toDouble();
    if (!continues) _historySize = 0;
    if (_historySize == _history) {
      _historyAt.setRange(0, _history - 1, _historyAt, 1);
      _historyMs.setRange(0, _history - 1, _historyMs, 1);
      _historySize--;
    }
    _historyAt[_historySize] = atMs;
    _historyMs[_historySize] = _anchorMs;
    _historySize++;
    _learnRate();
  }

  /// The rate, measured from the oldest reading within [_rateWindowMs] to the
  /// newest. Across seconds the player's jitter is a fraction of a percent,
  /// and a rate that is really changing — Automix easing a tempo back — is
  /// still followed within the window.
  void _learnRate() {
    final newest = _historySize - 1;
    if (newest < 1) return;
    var oldest = 0;
    while (oldest < newest && _historyAt[newest] - _historyAt[oldest] > _rateWindowMs) {
      oldest++;
    }
    final span = _historyAt[newest] - _historyAt[oldest];
    if (span >= _minRateSpanMs) {
      _rate = ((_historyMs[newest] - _historyMs[oldest]) / span).clamp(_minRate, _maxRate);
      _rateSettled = true;
      return;
    }
    // Not enough of a stretch yet: a rough step from the last two, so the
    // first second at 1.2x is not spent believing it is at 1x.
    final pairSpan = _historyAt[newest] - _historyAt[newest - 1];
    if (!_rateSettled && pairSpan >= _minPairSpanMs) {
      final measured = ((_historyMs[newest] - _historyMs[newest - 1]) / pairSpan)
          .clamp(_minRate, _maxRate);
      _rate += (measured - _rate) * _pairLearning;
    }
  }

  void _clearSuspect() {
    _suspectAtMs = double.nan;
    _rejections = 0;
  }

  void _advance(double nowMs, double dt) {
    final target = _targetAt(nowMs);
    // What this frame moves the words by on its own, and how far from the
    // song that leaves them.
    final step = dt * _rate;
    final error = target - (displayedMs + step);
    if (!_glideStartMs.isNaN) {
      final progress = (nowMs - _glideStartMs) / _glideMs;
      if (progress >= 1) {
        displayedMs = target;
        _glideStartMs = double.nan;
      } else {
        // The offset eases out while the target keeps moving, so the glide
        // lands on a playhead that is still running.
        displayedMs = target + _glideOffsetMs * (1 - _smoothstep(progress));
      }
    } else if (error <= -_lostMs || error >= _lostMs) {
      // Confirmed, unannounced, and far: the song is somewhere else entirely
      // and no amount of slowing down will get there.
      displayedMs = target;
    } else if (error >= _glideFromMs) {
      _startGlide(nowMs - dt, displayedMs - (target - step));
      displayedMs = target + _glideOffsetMs * (1 - _smoothstep(dt / _glideMs));
    } else {
      // Behind runs fast, ahead runs slow — and slow is floored well above
      // zero, so the words never stop to wait. The share of the gap closed
      // grows with the frame but never reaches all of it, so a long frame
      // after a stall cannot carry the words past the song.
      final closing = error * (dt / (dt + _correctionMs));
      displayedMs += step + closing.clamp(-_maxSlow * step, _maxSlew * step);
    }
  }

  /// An announced jump: rolled to over [_glideMs] when it is near, taken at
  /// once when it is not.
  void _jumpTo(double nowMs) {
    final offset = displayedMs - _targetAt(nowMs);
    if (offset.abs() > _glideMaxMs) {
      displayedMs = _targetAt(nowMs);
      _glideStartMs = double.nan;
    } else {
      _startGlide(nowMs, offset);
    }
  }

  void _startGlide(double startMs, double offsetMs) {
    _glideStartMs = startMs;
    _glideOffsetMs = offsetMs;
  }

  /// Where the song is at [atMs]: the newest reading believed, carried forward.
  double _targetAt(double atMs) => _anchorMs + (atMs - _anchorAtMs) * _rate;

  static double _smoothstep(double fraction) {
    final t = fraction.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// A dated reading this far off where the song should be is not noise.
  static const _outlierMs = 250.0;

  /// Extra allowance per millisecond between readings, for a rate not known
  /// exactly — and a wider one until it has been measured at all.
  static const _rateSlack = 0.2;
  static const _unsettledRateSlack = 0.75;

  /// Readings refused in a row before the next is taken whatever it says.
  static const _maxRejections = 2;

  /// The rate is measured across readings at least [_minRateSpanMs] and at
  /// most [_rateWindowMs] apart.
  static const _minRateSpanMs = 900.0;
  static const _rateWindowMs = 4000.0;
  static const _history = 16;

  /// Before then, a rough step from each pair at least this far apart.
  static const _minPairSpanMs = 300.0;
  static const _pairLearning = 0.5;

  /// Playback rates the clock may conclude; outside these is noise.
  static const _minRate = 0.25;
  static const _maxRate = 4.0;

  /// The gap closes with a time constant of [_correctionMs], capped at
  /// [_maxSlew] faster and [_maxSlow] slower.
  static const _correctionMs = 600.0;
  static const _maxSlew = 0.25;
  static const _maxSlow = 0.5;

  /// Behind by this much, the words catch up over [_glideMs] instead.
  static const _glideFromMs = 300.0;
  static const _glideMs = 260.0;

  /// An announced jump further than this is taken at once.
  static const _glideMaxMs = 2000.0;

  /// A confirmed gap this wide either way is another part of the song.
  static const _lostMs = 3000.0;
}

/// Drives a [LyricClock] from the active player for one frame: the reading,
/// shifted by the lyrics offset, its stamp, and whether it has jumped. Not
/// advancing (paused, loading, buffering), the clock holds on the reading,
/// so lyrics never run ahead of a song that hasn't started or has stalled.
int stepLyricClock(
  LyricClock clock,
  ({int positionMs, double sampledAtMs, bool advancing, int seeks}) playhead,
  int offsetMs,
) {
  final nowMs = DateTime.now().microsecondsSinceEpoch / 1000;
  final reportedMs = playhead.positionMs + offsetMs;
  if (!playhead.advancing) {
    clock.hold(reportedMs, nowMs);
    return reportedMs;
  }
  // Moving the offset shifts every reading at once; announced as a jump, it
  // isn't mistaken for a reading gone wrong.
  final discontinuity = (playhead.seeks << 20) ^ (offsetMs & 0xFFFFF);
  return clock.frame(nowMs, reportedMs, playhead.sampledAtMs, discontinuity);
}
