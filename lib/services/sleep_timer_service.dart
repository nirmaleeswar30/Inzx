import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_player_service.dart';

/// Stops the music after a set time: anything from 5 minutes to 12 hours.
///
/// The last ten seconds fade out rather than cut, then playback pauses (so
/// the queue and position are kept for the morning).
class SleepTimerService extends ChangeNotifier {
  SleepTimerService._();
  static final SleepTimerService instance = SleepTimerService._();

  static const Duration minimum = Duration(minutes: 5);
  static const Duration maximum = Duration(hours: 12);
  static const Duration _fade = Duration(seconds: 10);

  /// Picker stops: every 5 min up to an hour, every 15 to three hours,
  /// then every 30 to twelve.
  static final List<Duration> steps = [
    for (var m = 5; m <= 60; m += 5) Duration(minutes: m),
    for (var m = 75; m <= 180; m += 15) Duration(minutes: m),
    for (var m = 210; m <= 720; m += 30) Duration(minutes: m),
  ];

  DateTime? _endsAt;
  Duration? _total;
  Timer? _fire;
  Timer? _tick;

  bool get isActive => _endsAt != null;
  Duration? get total => _total;

  Duration? get remaining {
    final end = _endsAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void start(Duration duration) {
    final d = duration < minimum
        ? minimum
        : (duration > maximum ? maximum : duration);
    _cancelTimers();
    _total = d;
    _endsAt = DateTime.now().add(d);
    _fire = Timer(d - _fade, _expire);
    // A countdown on screen only needs to change once a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Adds time to a running timer, up to the 12-hour limit.
  void extend(Duration extra) {
    final left = remaining;
    if (left == null) return;
    start(left + extra);
  }

  void cancel() {
    _cancelTimers();
    _endsAt = null;
    _total = null;
    notifyListeners();
  }

  void _cancelTimers() {
    _fire?.cancel();
    _tick?.cancel();
    _fire = null;
    _tick = null;
  }

  Future<void> _expire() async {
    _fire = null;
    try {
      await AudioPlayerService().fadeOutAndPause(duration: _fade);
    } catch (e) {
      debugPrint('SleepTimer: pause failed: $e');
    }
    cancel();
  }

  /// "1 h 25 min", "40 min", "4:59" (under five minutes left, seconds too).
  static String format(Duration d, {bool precise = false}) {
    if (precise && d < const Duration(minutes: 5)) {
      final s = d.inSeconds;
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    final minutes = (d.inSeconds / 60).ceil();
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }
}
