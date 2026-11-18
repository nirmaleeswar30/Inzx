// Desktop Automix: the transition engine.
//
// Android runs BitChord's CrossfadeController natively over two ExoPlayers,
// riding each one's volume, tempo and transition filter live. Desktop's
// players (libmpv via media_kit) have no transition filters, so each blend
// is rendered instead (see blend_renderer.cpp) and played as one clip:
//
//   current song ──┐ clip: both songs, faded, filtered, beatmatched ┌── next song
//   (its player)   └───────── (the engine's own player) ─────────────┘ (the spare)
//
// The planning is BitChord's, ported (transition_planner.dart), and so is
// everything the blend does over its length (blend_automation.dart). The
// two hand-overs at the clip's edges are over identical audio: the clip
// opens on the outgoing song exactly as its player is playing it, and
// closes on the incoming song exactly where the spare player picks it up,
// each crossed over a few milliseconds once both are measured in step.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'automix_native.dart';
import 'blend_automation.dart';
import 'blend_clip_player.dart';
import 'desktop_track_analyzer.dart';
import 'loop_mix.dart';
import 'track_analysis.dart';
import 'transition_planner.dart';

/// What a player has loaded, for decoding the same audio it plays.
class DecodeSource {
  const DecodeSource(this.uri, [this.headers = const {}]);
  final String uri;
  final Map<String, String> headers;
}

/// What the engine needs from the player service.
abstract class DesktopAutomixHost {
  Duration positionOf(String playerId);
  Duration? durationOf(String playerId);
  bool isPlaying(String playerId);
  double get listenerSpeed;
  DecodeSource? sourceOf(String playerId);

  /// Loads queue entry [index] onto [playerId] at [at], silent and paused.
  Future<bool> loadIncoming(String playerId, int index, Duration at);
  Future<void> setVolume(String playerId, double volume);
  Future<void> setSpeed(String playerId, double speed);
  Future<void> seek(String playerId, Duration at);
  void play(String playerId);
  Future<void> pause(String playerId);
  Future<void> retire(String playerId);

  /// Whether [playerId] is set to play, buffering or not.
  bool wantsToPlay(String playerId);

  /// iOS mixes live, BitChord-iOS's way, rather than through a rendered
  /// clip: both songs play on their own players while the engine rides
  /// their volumes and transition filters.
  bool get mixesLive;

  /// A live blend's transition filter on [playerId]; the defaults park it.
  void setTransitionFilter(String playerId,
      {double lowPassHz = 20000, double highPassHz = 20, double echoSeconds = 0, double echoSend = 0, double echoDry = 1});

  /// A live blend's midpoint: the incoming song is now the current one,
  /// with the outgoing still fading on the other player.
  void liveHandoff(String toPlayerId, int index);

  /// The clip is now what's heard; [clipProgress] carries the UI through it.
  void clipBegan();
  void clipProgress(int index, Duration position, bool playing);
  /// The blend's midpoint: the incoming song is now the current one.
  void clipHandoff(String toPlayerId, int index);
  /// The clip is over; [sessionPlayerId] is the song now.
  void clipEnded(String sessionPlayerId);

  Future<void> fetchAudio(String videoId);

  /// Line-synced lyrics for [videoId] (fetched if need be), or null when it
  /// has none; the loop mix keeps its loops off sung lines with them.
  Future<List<LoopLyricLine>?> syncedLyrics(String videoId);

  /// Loudness normalization's linear gain for [trackId] (1 when off). The
  /// players carry it for normal playback; a rendered blend bakes each
  /// side's in, since one clip player plays both songs.
  double loudnessGain(String trackId);
  double get masterVolume;
  String get scratchDir;
}

class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.isVideo,
  });
  final String id;
  final String title;
  final String artist;
  final int durationMs;
  final bool isVideo;
}

enum _Phase { idle, rendering, armed, clip, live, easing }

/// Everything one blend needs, fixed when it's armed.
class _Blend {
  _Blend({
    required this.plan,
    required this.render,
    required this.outgoingIndex,
    required this.incomingIndex,
    required this.outgoingId,
    required this.incomingId,
    required this.outPlayer,
    required this.inPlayer,
    required this.tStart,
    required this.span,
    required this.rate,
    required this.cue,
    required this.outgoingDuration,
    this.loop,
  });
  /// Set for a loop mix rather than a blend.
  final LoopMixClock? loop;
  final TransitionPlan plan;
  final Render render;
  final int outgoingIndex;
  final int incomingIndex;
  final String outgoingId;
  final String incomingId;
  final String outPlayer;
  final String inPlayer;
  /// Outgoing seconds where the clip begins.
  final double tStart;
  /// Clip seconds the blend runs for.
  final double span;
  /// The incoming song's stretch through the blend.
  final double rate;
  /// Incoming seconds the clip begins on.
  final double cue;
  final double outgoingDuration;
  String? clipPath;
  bool handedOff = false;

  /// Played live on the two players rather than as a rendered clip.
  bool live = false;
  /// Live: the incoming song's position when it started, and when that was.
  double liveCue = 0;
  DateTime? liveStartedAt;
  bool latencyMeasured = false;

  /// How far each song's playing source runs ahead of the copy it was
  /// analysed from (a JioSaavn or lossless master against the YouTube one),
  /// in seconds. The plan is in analysis time; players are in source time.
  double offOut = 0;
  double offIn = 0;

  /// The outgoing song's source second the clip opens on.
  double get outStart => tStart + offOut;
  /// The incoming song's source second clip second [t] plays.
  double incomingAt(double t) {
    final loop = this.loop;
    if (loop != null) return (loop.incomingAt(t) ?? loop.plan.inn.loopStart) + offIn;
    return cue + offIn + t * rate;
  }

  /// The outgoing song's source second clip second [t] plays (a loop mix
  /// keeps going round its loop).
  double outgoingAt(double t) {
    final loop = this.loop;
    if (loop != null) return (loop.outgoingAt(t) ?? loop.plan.out.loopEnd) + offOut;
    return outStart + t;
  }

  /// Whether the incoming song is the current one by clip second [t].
  bool handoffDue(double t) {
    final loop = this.loop;
    if (loop != null) return t >= loop.handoffAt;
    return progressAt(t) >= render.handoffAt;
  }

  bool get isRealMix => loop != null || render.isRealMix(plan);

  /// Clip seconds rendered: the blend, then a little of the incoming song
  /// alone so the closing hand-over has room.
  double get clipSeconds => span + _tailSeconds;
  /// Where the spare player takes over on the incoming song.
  double get resumeAt => incomingAt(span);

  /// How far through the blend clip second [t] is.
  double progressAt(double t) {
    if (loop != null) return (t / span).clamp(0.0, 1.0);
    final byTime = t / span;
    final outRemaining = outgoingDuration - tStart - t;
    final byEnd = (span - outRemaining) / span;
    return math.max(byTime, byEnd).clamp(0.0, 1.0);
  }
}

const double _tailSeconds = 0.6;
const double _prerollSeconds = 1.0;
const int _renderRate = 48000;
const double _envelopeStep = 0.005;
const Duration _armLead = Duration(seconds: 25);
const Duration _minArmLead = Duration(milliseconds: 2500);
const Duration _crossoverTime = Duration(milliseconds: 80);
// A seek onto (or into) the window still mixes, as on Android: a rendered
// blend is joined part-way when it's ready, so long as this much of it is
// left by then; a live one starts at once.
const double _lateJoinMargin = 1.0;
const double _renderAllowance = 2.0;
// CrossfadeController's loop-mix lead times.
const Duration _loopMinLead = Duration(seconds: 9);
const double _loopSetupSeconds = 15.0;

class DesktopAutomixEngine {
  DesktopAutomixEngine({required this.host, required this.analyzer}) {
    _analysisLanded = analyzer.landed.listen((_) => _planSoon());
    _purgeClips();
  }

  /// Clips are only ever played once; any left over from a run that ended
  /// mid-blend go when the next one starts.
  void _purgeClips() {
    try {
      final dir = Directory(host.scratchDir);
      if (!dir.existsSync()) return;
      for (final file in dir.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        if (name.startsWith('automix_blend_') || name.startsWith('decode_')) file.deleteSync();
      }
    } catch (_) {}
  }

  /// Deletes a played clip once its player has let go of the file.
  static void _discardClip(String? path) {
    if (path == null) return;
    Future<void>.delayed(const Duration(seconds: 2), () => _deleteQuietly(path));
  }

  final DesktopAutomixHost host;
  final DesktopTrackAnalyzer analyzer;
  late final StreamSubscription<String> _analysisLanded;

  bool _enabled = false;
  bool _inJam = false;
  List<QueueEntry> _queue = const [];
  String? _primary;
  String? _secondary;
  String? _active;
  int _index = -1;
  String _repeat = 'off';

  _Phase _phase = _Phase.idle;
  _Blend? _blend;
  int _generation = 0;
  Timer? _ticker;
  BlendClipPlayer? _clipPlayer;
  final Set<String> _fetchAsked = {};
  /// A pair whose blend couldn't be armed isn't tried again this play.
  String? _failedPair;
  /// Why the last blend didn't happen, for the stats line; cleared when one
  /// gets under way.
  String? _lastIssue;

  // Published for the player UI.
  TransitionPlan? _lastPlan;
  double? _windowStart;
  double? _windowEnd;
  double _mixProgress = 0;
  bool _mixing = false;

  // Tempo ease-back after a stretched blend.
  String? _easePlayer;
  double _easeRate = 1.0;
  double _easeStep = 0.0;
  int _easeStepMs = 500;
  int _easeNextAtMs = 0;

  bool get clipActive => _phase == _Phase.clip;
  bool get transitioning => _phase != _Phase.idle && _phase != _Phase.easing;

  set enabled(bool on) {
    if (_enabled == on) return;
    _enabled = on;
    if (!on) _abort('automix off');
    _schedule();
  }

  /// A Jam, or "Play on both" over Inzx Connect: nothing mixes or analyses.
  set inJam(bool value) {
    if (_inJam == value) return;
    _inJam = value;
    analyzer.stopped = value;
    if (value) {
      _abort('paused: Jam or playing on both');
    } else {
      _schedule();
    }
  }

  bool _exclusive = false;

  /// Bit-perfect (exclusive) output: the device takes one stream, so
  /// nothing mixes while it's on (Android's rule too).
  set exclusiveOutput(bool value) {
    if (_exclusive == value) return;
    _exclusive = value;
    if (value) _abort('bit-perfect output');
    _schedule();
  }

  void dispose() {
    _ticker?.cancel();
    unawaited(_analysisLanded.cancel());
    unawaited(_clipPlayer?.dispose());
  }

  /// The blend player, with the equaliser / AutoEQ chain the others run.
  BlendClipPlayer _createClipPlayer() => BlendClipPlayer.forPlatform();

  // ---- From the player service --------------------------------------------

  void sync({
    required String primary,
    required String secondary,
    required String active,
    required int index,
    required List<QueueEntry> queue,
    required String repeat,
  }) {
    final moved = _active != null && (index != _index || active != _active);
    _primary = primary;
    _secondary = secondary;
    _queue = queue;
    _repeat = repeat;
    // A change the engine didn't make (a tap, a skip, a queue edit) drops a
    // blend that hasn't been heard yet.
    if (moved && (_phase == _Phase.rendering || _phase == _Phase.armed)) {
      final blend = _blend;
      final stillOurs = blend != null && index == blend.outgoingIndex && active == blend.outPlayer;
      if (!stillOurs) _abort('queue moved');
    }
    if (moved && _phase == _Phase.easing && active != _easePlayer) _endEase();
    _active = active;
    _index = index;
    _schedule();
  }

  void audioCached(String videoId, String path) => analyzer.registerAudio(videoId, path);

  void request(String videoId, Duration duration) {
    if (!_enabled || _inJam || _exclusive) return;
    analyzer.request(videoId, duration.inMilliseconds / 1000.0);
    // Wanted even once an analysis is restored from disk: a blend measures
    // the playing source against this copy (see _measureOffset). Free when
    // it's already cached.
    if (!analyzer.hasAudio(videoId) && _fetchAsked.add(videoId)) unawaited(host.fetchAudio(videoId));
  }

  /// The listener asked for another song, or moved the playhead: whatever
  /// the blend was doing, the song carries on plainly.
  Future<void> skip() async => _abort('skip');

  /// The listener moved the playhead. A live blend is dropped (the song
  /// that's current carries on), and one armed but not yet started is
  /// planned afresh from the new position, which re-arms it at once when
  /// the seek landed on the marker. A rendered clip waits for its start (see
  /// [_driveArmed]); a seek during one goes through [leaveClip].
  Future<void> seeked() async {
    if (_phase == _Phase.live) {
      await _abort('seek');
    } else if (host.mixesLive && (_phase == _Phase.rendering || _phase == _Phase.armed)) {
      await _bail();
    }
  }

  /// Pause and play during the clip act on the clip.
  Future<void> clipPlay() async {
    _clipPlayer?.play();
    _publishClip();
  }

  Future<void> clipPause() async {
    await _clipPlayer?.pause();
    _publishClip();
  }

  /// A seek during the clip: leave it for whichever song is current and let
  /// the service seek that player. Returns the player that's the song now.
  Future<String?> leaveClip() async {
    final blend = _blend;
    if (_phase != _Phase.clip || blend == null) return null;
    final t = _clipSeconds();
    final playing = _clipPlayer?.playing ?? false;
    _generation++;
    _phase = _Phase.idle;
    _mixing = false;
    final String session;
    if (blend.handedOff) {
      session = blend.inPlayer;
      await host.seek(session, _seconds(blend.incomingAt(t)));
      await host.setSpeed(session, host.listenerSpeed);
      await host.setVolume(session, 1.0);
      await host.retire(blend.outPlayer);
    } else {
      session = blend.outPlayer;
      await host.seek(session, _seconds(blend.outgoingAt(t)));
      await host.setVolume(session, 1.0);
      await host.retire(blend.inPlayer);
    }
    if (playing) host.play(session);
    await _stopClip();
    host.clipEnded(session);
    _blend = null;
    _discardClip(blend.clipPath);
    return session;
  }

  // ---- For the UI ---------------------------------------------------------

  Map<String, Object?>? mixState() {
    if (!_enabled) return null;
    final blend = _blend;
    double? beatMs;
    double? sinceBeatMs;
    bool? blendPlaying;
    if (_phase == _Phase.clip && blend != null) {
      final t = _clipSeconds();
      final speed = host.listenerSpeed;
      final dominant = blend.handedOff
          ? analyzer.analysisFor(blend.incomingId)
          : analyzer.analysisFor(blend.outgoingId);
      final position = blend.handedOff ? blend.cue + t * blend.rate : blend.tStart + t;
      final rate = blend.handedOff ? blend.rate : 1.0;
      final loop = blend.loop;
      final (int, double)? loopBeat;
      if (loop != null && t < loop.beatTimes.last) {
        final (k, frac) = loop.beatAt(t);
        final length = k >= 0 && k + 1 < loop.beatTimes.length ? loop.beatTimes[k + 1] - loop.beatTimes[k] : 0.0;
        loopBeat = length > 0 ? (k, length) : null;
        if (loopBeat != null) {
          beatMs = length / speed * 1000;
          sinceBeatMs = frac * length / speed * 1000;
        }
      } else {
        loopBeat = null;
      }
      final beat = loopBeat != null ? null : _beatAt(dominant, position);
      if (beat != null) {
        beatMs = beat.$2 / rate / speed * 1000;
        sinceBeatMs = beat.$1 / rate / speed * 1000;
      }
      blendPlaying = _clipPlayer?.playing ?? false;
    }
    return {
      'mixing': _mixing,
      'progress': _mixProgress,
      'windowStart': _phase == _Phase.clip ? null : _windowStart,
      'windowEnd': _phase == _Phase.clip ? null : _windowEnd,
      'beatMs': beatMs,
      'sinceBeatMs': sinceBeatMs,
      'blendPlaying': blendPlaying,
    };
  }

  Map<String, Object?> describe(String videoId) {
    final analysis = analyzer.analysisFor(videoId);
    return {
      'analysed': analyzer.isAnalysed(videoId),
      'analysing': analyzer.isAnalysing(videoId),
      'hasAudio': analyzer.hasAudio(videoId),
      'usable': analysis.isUsable,
      'bpm': analysis.bpm,
      'beatConfidence': analysis.beatConfidence,
      'key': analysis.key,
      'mixIn': analysis.mixInTime,
      'mixOut': analysis.mixOutTime,
      'modelGrid': analysis.headBeats != null || analysis.tailBeats != null,
    };
  }

  /// AutomixBridge.statsLine's wording.
  String? statsLine(String current, String? next) {
    if (!_enabled || _inJam || _exclusive) return null;
    String label(String? id, bool outgoing) {
      if (id == null) return 'none';
      final analysis = analyzer.analysisFor(id);
      final analysing = analyzer.isAnalysing(id);
      if (!analysis.isUsable) {
        if (analysing) return 'analysing…';
        if (analyzer.isAnalysed(id)) return 'failed';
        return 'waiting';
      }
      final side = outgoing ? analysis.tailBeats : analysis.headBeats;
      final bpm = side?.bpm ?? analysis.bpm;
      final confidence = side?.confidence ?? analysis.beatConfidence;
      final key = analysis.key.trim().isEmpty ? '' : ' ${analysis.key}';
      final grid = side != null ? 'model grid' : 'dsp grid';
      final refining = analysing ? ', refining' : '';
      return 'analysed (${bpm.round()} BPM$key, $grid ${confidence.toStringAsFixed(2)}$refining)';
    }

    final plan = _lastPlan;
    final planned = plan != null && !plan.blocked && _windowStart != null
        ? ' · ${_styleName(plan)} ${plan.fadeSeconds.toStringAsFixed(1)}s'
            '${plan.incomingPlaybackRate != 1.0 ? ' @${plan.incomingPlaybackRate.toStringAsFixed(3)}x' : ''}'
        : '';
    final issue = _lastIssue == null ? '' : ' · last: $_lastIssue';
    return 'Automix · this song: ${label(current, true)} · next: ${label(next, false)}$planned$issue';
  }

  static String _styleName(TransitionPlan plan) => switch (plan.transitionStyle) {
        TransitionStyle.djBlend => plan.bassSwap ? 'blend, bass swap' : 'blend',
        TransitionStyle.djFilter => switch (plan.filterVariant) {
            FilterTransitionVariant.bassHandoff => 'filter, bass handoff',
            _ => 'filter sweep',
          },
        TransitionStyle.gapless => 'gapless',
        TransitionStyle.equalPower => 'crossfade',
      };

  // ---- The loop ---------------------------------------------------------------

  void _planSoon() => _schedule(immediate: true);

  void _schedule({bool immediate = false}) {
    final wanted = _enabled && !_inJam && !_exclusive;
    if (!wanted && _phase == _Phase.idle) {
      _ticker?.cancel();
      _ticker = null;
      _windowStart = _windowEnd = null;
      return;
    }
    final fast = _phase == _Phase.armed || _phase == _Phase.clip || _phase == _Phase.live;
    final period = Duration(milliseconds: fast ? 15 : (_phase == _Phase.easing ? 100 : 250));
    if (_ticker == null || _tickerPeriod != period) {
      _ticker?.cancel();
      _tickerPeriod = period;
      _ticker = Timer.periodic(period, (_) => _tick());
    }
    if (immediate) scheduleMicrotask(_tick);
  }

  Duration? _tickerPeriod;
  bool _ticking = false;

  void _tick() {
    if (_ticking) return;
    _ticking = true;
    try {
      switch (_phase) {
        case _Phase.idle:
          _considerTransition();
        case _Phase.rendering:
          break;
        case _Phase.armed:
          _driveArmed();
        case _Phase.clip:
          _driveClip();
        case _Phase.live:
          _driveLive();
        case _Phase.easing:
          _driveEase();
          _considerTransition();
      }
    } finally {
      _ticking = false;
    }
  }

  int? _nextIndex() {
    if (_index < 0 || _queue.isEmpty) return null;
    if (_repeat == 'one') return null;
    if (_index + 1 < _queue.length) return _index + 1;
    if (_repeat == 'all') return 0;
    return null;
  }

  void _considerTransition() {
    if (!_enabled || _inJam || _exclusive) return;
    final active = _active;
    if (active == null || _index < 0 || _index >= _queue.length) return;
    final current = _queue[_index];
    final nextIndex = _nextIndex();
    if (nextIndex == null || current.isVideo || _queue[nextIndex].isVideo) {
      _windowStart = _windowEnd = null;
      return;
    }
    final next = _queue[nextIndex];
    final duration = host.durationOf(active) ?? Duration(milliseconds: current.durationMs);
    if (duration <= Duration.zero) return;

    request(current.id, duration);
    request(next.id, Duration(milliseconds: next.durationMs));

    final position = host.positionOf(active);
    final currentAnalysis = analyzer.analysisFor(current.id);
    final nextAnalysis = analyzer.analysisFor(next.id);
    final plan = planTransition(
      analysis: currentAnalysis,
      nextAnalysis: nextAnalysis,
      currentTrack: TransitionTrackInfo(
          id: current.id, durationMs: duration.inMilliseconds, title: current.title, artist: current.artist),
      nextTrack: TransitionTrackInfo(
          id: next.id, durationMs: next.durationMs, title: next.title, artist: next.artist),
      currentTime: position.inMilliseconds / 1000.0,
      duration: duration.inMilliseconds / 1000.0,
      fadeSeconds: 6.0,
      mode: CrossfadeMode.smart,
      advanced: true,
    );
    _lastPlan = plan;

    final markable = !plan.blocked &&
        plan.markerVisible &&
        currentAnalysis.isUsable &&
        analyzer.isAnalysed(next.id);
    if (markable) {
      final ms = duration.inMilliseconds;
      _windowStart = (plan.transitionStart * 1000 / ms).clamp(0.0, 1.0);
      _windowEnd = (plan.transitionEnd * 1000 / ms).clamp(0.0, 1.0);
    } else {
      _windowStart = _windowEnd = null;
    }

    final spareFor = active == _primary ? _secondary : _primary;
    final loop = _loopPlanFor(active, current, next, currentAnalysis, nextAnalysis, duration, position);
    if (loop != null) {
      final loopStartMs = (loop.out.loopStart * 1000).round();
      _windowStart = (loopStartMs / duration.inMilliseconds).clamp(0.0, 1.0);
      _windowEnd = 1.0;
      if (_phase != _Phase.idle || !host.isPlaying(active) || spareFor == null) return;
      final remaining = Duration(milliseconds: loopStartMs) - position;
      if (remaining > _armLead || remaining < _minArmLead) return;
      unawaited(_armLoop(loop, nextIndex, active, spareFor, duration));
      return;
    }

    if (_phase != _Phase.idle || plan.blocked || plan.fadeMs <= 0) return;
    if (!host.isPlaying(active)) return;
    final startMs = (plan.transitionStart * 1000).round();
    final remaining = Duration(milliseconds: startMs) - position;
    if (remaining > _armLead) return;
    if (remaining < _minArmLead) {
      // Too close to render ahead: a seek onto the marker, or a stall. Arm
      // anyway while there's still a blend to join when it's ready.
      final at = position.inMilliseconds / 1000.0;
      final room = host.mixesLive ? _lateJoinMargin : _renderAllowance + _lateJoinMargin;
      if (at > plan.transitionEnd - room) return;
    }
    final spare = active == _primary ? _secondary : _primary;
    if (spare == null) return;
    if (_failedPair == '${current.id}>${next.id}') return;
    unawaited(_arm(plan, nextIndex, active, spare, duration));
  }

  // ---- The loop mix -------------------------------------------------------------

  final Map<String, List<SungSpan>?> _lyricSpans = {};
  final Set<String> _lyricsAsked = {};
  String? _loopKey;
  LoopMixPlan? _loopPlanned;
  String _loopVerdict = '';
  /// Pairs a loop mix turned out not to suit (a source that isn't the
  /// analysed recording): they get a blend instead.
  final Set<String> _noLoopPairs = {};

  void _askLyrics(String id) {
    if (!_lyricsAsked.add(id)) return;
    unawaited(host.syncedLyrics(id).then((lines) {
      // Only line-synced lyrics say where a voice is.
      final timed = lines?.where((l) => l.timeMs > 0).length ?? 0;
      _lyricSpans[id] = lines != null && timed >= 4 ? LoopMix.sungSpans(lines) : null;
      _planSoon();
    }).catchError((Object _) {
      _lyricSpans[id] = null;
    }));
  }

  /// A source the analysis was measured on: the analysed file itself or the
  /// YouTube stream it came from. A loop is cut from the audio that plays,
  /// so a different recording (JioSaavn, lossless) can't carry one.
  bool _canonical(String id, DecodeSource? source) {
    if (source == null) return false;
    final uri = _decodable(source.uri);
    if (uri.contains('googlevideo.com')) return true;
    final analysed = analyzer.audioFor(id);
    // Compared as paths: the cache hands out "Temp/stream_audio_cache/x"
    // while the player's file URI comes back as "Temp\stream_audio_cache\x".
    return analysed != null && !uri.contains('://') && p.equals(uri, analysed);
  }

  /// CrossfadeController.loopPlanFor: the loop mix for this pair, or null.
  LoopMixPlan? _loopPlanFor(String active, QueueEntry current, QueueEntry next, TrackAnalysis currentAnalysis,
      TrackAnalysis nextAnalysis, Duration duration, Duration position) {
    final pair = '${current.id}>${next.id}';
    String? refusal;
    if (AutomixNative.instance == null) {
      refusal = 'no renderer';
    } else if ((host.listenerSpeed - 1.0).abs() > 1e-6) {
      refusal = 'playback speed is not 1x';
    } else if (!currentAnalysis.isUsable || !nextAnalysis.isUsable) {
      refusal = 'waiting on analysis';
    } else if (_noLoopPairs.contains(pair) || !_canonical(current.id, host.sourceOf(active))) {
      final src = host.sourceOf(active);
      refusal = 'analysed off another recording '
          '(playing ${src == null ? 'an unreadable source' : _decodable(src.uri)}, '
          'analysed ${analyzer.audioFor(current.id) ?? 'nothing'})';
    }
    if (refusal == null) {
      _askLyrics(current.id);
      _askLyrics(next.id);
      if (!_lyricSpans.containsKey(current.id) || !_lyricSpans.containsKey(next.id)) refusal = 'waiting on lyrics';
    }
    if (refusal != null) {
      _noteLoop('$pair: no loop mix ($refusal)');
      return null;
    }
    final key = '$pair|${identityHashCode(currentAnalysis)}|${identityHashCode(nextAnalysis)}';
    final cached = _loopPlanned;
    if (key == _loopKey &&
        (cached == null || cached.out.loopStart * 1000 - position.inMilliseconds >= _loopMinLead.inMilliseconds)) {
      return cached;
    }
    final why = StringBuffer();
    final plan = LoopMix.plan(
      out: currentAnalysis,
      outDuration: duration.inMilliseconds / 1000.0,
      inn: nextAnalysis,
      inDuration: next.durationMs / 1000.0,
      earliestOutSec: position.inMilliseconds / 1000.0 + _loopSetupSeconds,
      sungOut: _lyricSpans[current.id],
      sungIn: _lyricSpans[next.id],
      why: why,
    );
    _loopKey = key;
    _loopPlanned = plan;
    _noteLoop(plan == null
        ? '$pair: no loop mix ($why)'
        : '$pair: loop mix at ${plan.out.loopStart.toStringAsFixed(2)}s · ${plan.describe()}');
    return plan;
  }

  void _noteLoop(String verdict) {
    if (verdict == _loopVerdict) return;
    _loopVerdict = verdict;
    debugPrint('Automix: loop $verdict');
  }

  Future<void> _armLoop(LoopMixPlan plan, int nextIndex, String outPlayer, String inPlayer, Duration duration) async {
    final generation = ++_generation;
    _phase = _Phase.rendering;
    _endEase();
    final current = _queue[_index];
    final next = _queue[nextIndex];
    final clock = LoopMixClock(plan);
    final blend = _Blend(
      plan: const TransitionPlan(),
      render: Render(),
      outgoingIndex: _index,
      incomingIndex: nextIndex,
      outgoingId: current.id,
      incomingId: next.id,
      outPlayer: outPlayer,
      inPlayer: inPlayer,
      tStart: plan.out.loopStart,
      span: clock.elementAt,
      rate: 1.0,
      cue: plan.inn.loopStart,
      outgoingDuration: duration.inMilliseconds / 1000.0,
      loop: clock,
    );
    _blend = blend;
    debugPrint('Automix: arming loop mix ${current.id} -> ${next.id} at ${plan.out.loopStart.toStringAsFixed(2)}s, '
        '${clock.elementAt.toStringAsFixed(1)}s long · ${plan.describe()}');
    bool stale() => generation != _generation;
    try {
      final outSource = host.sourceOf(outPlayer);
      if (outSource == null) throw StateError('no source for the playing song');
      final loaded = await host.loadIncoming(inPlayer, nextIndex, _seconds(blend.resumeAt));
      if (stale()) return;
      if (!loaded) throw StateError('incoming song would not load');
      await host.setSpeed(inPlayer, host.listenerSpeed);
      final inSource = host.sourceOf(inPlayer);
      if (!_canonical(next.id, inSource)) {
        // The incoming song plays another recording: a blend it is.
        _noLoopPairs.add('${current.id}>${next.id}');
        debugPrint('Automix: loop mix dropped, the incoming song plays another recording');
        if (!stale()) await _bail();
        return;
      }
      final scratch = host.scratchDir;
      await Directory(scratch).create(recursive: true);
      final clipPath = p.join(scratch, 'automix_blend_${generation}_${DateTime.now().millisecondsSinceEpoch}.wav');
      final job = _LoopJob(
        outUri: outSource.uri,
        outHeaders: outSource.headers,
        inUri: inSource!.uri,
        inHeaders: inSource.headers,
        plan: plan,
        clipSeconds: blend.clipSeconds,
        scratch: scratch,
        clipPath: clipPath,
        outLevel: host.loudnessGain(current.id),
        inLevel: host.loudnessGain(next.id),
      );
      final began = DateTime.now();
      final report = await _renderLoopOffThread(job);
      if (stale()) {
        _deleteQuietly(clipPath);
        return;
      }
      if (report != null) throw StateError(report);
      debugPrint('Automix: rendered ${blend.clipSeconds.toStringAsFixed(1)}s loop mix in '
          '${DateTime.now().difference(began).inMilliseconds}ms');
      blend.clipPath = clipPath;
      final clip = _clipPlayer ??= _createClipPlayer();
      await clip.setGain(0);
      await clip.setRate(host.listenerSpeed);
      await clip.open(clipPath);
      await _waitFor(() => clip.duration > Duration.zero, const Duration(seconds: 3));
      if (stale()) return;
      _phase = _Phase.armed;
      _schedule();
    } catch (e) {
      debugPrint('Automix: loop mix failed: $e');
      _lastIssue = 'loop mix failed: $e';
      _noLoopPairs.add('${current.id}>${next.id}');
      if (!stale()) await _bail();
    }
  }

  // ---- Arming: load the spare, decode both sides, render -----------------

  Future<void> _arm(TransitionPlan plan, int nextIndex, String outPlayer, String inPlayer, Duration duration) async {
    if (host.mixesLive) return _armLive(plan, nextIndex, outPlayer, inPlayer, duration);
    final generation = ++_generation;
    _phase = _Phase.rendering;
    _endEase();
    final current = _queue[_index];
    final next = _queue[nextIndex];
    final outgoingSeconds = duration.inMilliseconds / 1000.0;

    // driveFade's span: never more than a third of what the incoming song
    // has left after its cue.
    final nextSeconds = next.durationMs / 1000.0;
    final incomingCap = nextSeconds > 0 ? math.max(0.0, nextSeconds - plan.incomingCueTime) / 3 : double.infinity;
    final span = math.max(0.05, math.min(plan.fadeSeconds, incomingCap));
    final blend = _Blend(
      plan: plan,
      render: Render.forPlan(plan),
      outgoingIndex: _index,
      incomingIndex: nextIndex,
      outgoingId: current.id,
      incomingId: next.id,
      outPlayer: outPlayer,
      inPlayer: inPlayer,
      tStart: plan.transitionStart,
      span: math.min(span, math.max(0.05, outgoingSeconds - plan.transitionStart)),
      rate: plan.incomingPlaybackRate,
      cue: plan.incomingCueTime,
      outgoingDuration: outgoingSeconds,
    );
    _blend = blend;
    debugPrint('Automix: arming ${current.id} -> ${next.id}: ${_styleName(plan)} '
        'at ${blend.tStart.toStringAsFixed(2)}s for ${blend.span.toStringAsFixed(2)}s, '
        'cue ${blend.cue.toStringAsFixed(2)}s @${blend.rate}x (${plan.reason})');

    bool stale() => generation != _generation;
    try {
      final outSource = host.sourceOf(outPlayer);
      if (outSource == null) throw StateError('no source for the playing song');
      final loaded = await host.loadIncoming(inPlayer, nextIndex, _seconds(blend.resumeAt));
      if (stale()) return;
      if (!loaded) throw StateError('incoming song would not load');
      await host.setSpeed(inPlayer, host.listenerSpeed * blend.rate);
      final inSource = host.sourceOf(inPlayer);
      if (inSource == null) throw StateError('no source for the incoming song');

      final scratch = host.scratchDir;
      await Directory(scratch).create(recursive: true);
      final clipPath = p.join(scratch, 'automix_blend_${generation}_${DateTime.now().millisecondsSinceEpoch}.wav');
      final job = _RenderJob(
        outUri: outSource.uri,
        outHeaders: outSource.headers,
        inUri: inSource.uri,
        inHeaders: inSource.headers,
        tStart: blend.tStart,
        cue: blend.cue,
        rate: blend.rate,
        span: blend.span,
        clipSeconds: blend.clipSeconds,
        outgoingDuration: blend.outgoingDuration,
        plan: plan,
        scratch: scratch,
        clipPath: clipPath,
        outCopy: analyzer.audioFor(current.id),
        inCopy: analyzer.audioFor(next.id),
        outLevel: host.loudnessGain(current.id),
        inLevel: host.loudnessGain(next.id),
      );
      final began = DateTime.now();
      final result = await _renderOffThread(job);
      final ok = result.ok;
      debugPrint('Automix: render: ${result.report}');
      blend.offOut = result.offOut;
      blend.offIn = result.offIn;
      if (stale()) {
        _deleteQuietly(clipPath);
        return;
      }
      if (!ok) throw StateError(result.report);
      debugPrint('Automix: rendered ${blend.clipSeconds.toStringAsFixed(1)}s blend in '
          '${DateTime.now().difference(began).inMilliseconds}ms');
      blend.clipPath = clipPath;

      final clip = _clipPlayer ??= _createClipPlayer();
      await clip.setGain(0);
      await clip.setRate(host.listenerSpeed);
      await clip.open(clipPath);
      await _waitFor(() => clip.duration > Duration.zero, const Duration(seconds: 3));
      if (stale()) return;
      _phase = _Phase.armed;
      _schedule();
    } catch (e) {
      debugPrint('Automix: arming failed: $e');
      _lastIssue = 'blend failed: $e';
      _failedPair = '${current.id}>${next.id}';
      if (!stale()) await _bail();
    }
  }

  // ---- The opening hand-over: the outgoing player into the clip --------------

  void _driveArmed() {
    final blend = _blend;
    if (blend == null) return;
    if (!host.isPlaying(blend.outPlayer)) return; // paused: wait
    final position = host.positionOf(blend.outPlayer).inMicroseconds / 1e6;
    if (blend.live) {
      // Early by the incoming player's start latency (BitChord-iOS).
      if (position < blend.outStart - _liveLatency * host.listenerSpeed) return;
      if (position > blend.tStart + blend.span - _lateJoinMargin) {
        _lastIssue = 'missed the blend (at ${position.toStringAsFixed(1)}s)';
        unawaited(_bail());
        return;
      }
      _startLive(blend);
      return;
    }
    if (position < blend.outStart - 0.005) return;
    // Late (a seek onto the marker, or a slow render): join the clip
    // part-way, as long as there's still some of it to hear.
    if (position > blend.outStart + math.max(1.0, blend.span - _lateJoinMargin)) {
      // Missed it (a stall or a seek past the start): no blend this time.
      _lastIssue = 'missed the blend start (at ${position.toStringAsFixed(1)}s, wanted ${blend.outStart.toStringAsFixed(1)}s)';
      unawaited(_bail());
      return;
    }
    _phase = _Phase.clip;
    unawaited(_openClip(blend, _generation));
  }

  Future<void> _openClip(_Blend blend, int generation) async {
    final clip = _clipPlayer;
    if (clip == null) return;
    bool stale() => generation != _generation;
    double outgoingClipTime() => host.positionOf(blend.outPlayer).inMicroseconds / 1e6 - blend.outStart;

    await clip.seek(_seconds(math.max(0.0, outgoingClipTime())));
    await clip.play();
    await _waitFor(() => clip.playing && clip.position > Duration.zero, const Duration(milliseconds: 1500));
    if (stale()) return;
    if (!clip.playing || clip.position <= Duration.zero) {
      // Nothing to cross into: the song carries on rather than going quiet.
      _lastIssue = 'the blend clip would not start';
      debugPrint('Automix: ${_lastIssue!}');
      await _bail();
      return;
    }
    await _align(() => clip.position.inMicroseconds / 1e6, outgoingClipTime, (to) => clip.seek(_seconds(to)));
    if (stale()) return;

    await _crossover(
      fadeOut: (v) => host.setVolume(blend.outPlayer, v),
      fadeIn: (v) => clip.setGain(v * host.masterVolume),
    );
    if (stale()) return;
    await host.pause(blend.outPlayer);
    _mixing = blend.isRealMix;
    _windowStart = _windowEnd = null;
    host.clipBegan();
    _lastIssue = null;
    _schedule();
    debugPrint('Automix: blend under way');
  }

  // ---- Through the clip ----------------------------------------------------------

  double _clipSeconds() => (_clipPlayer?.position.inMicroseconds ?? 0) / 1e6;

  void _publishClip() {
    final blend = _blend;
    if (blend == null || _phase != _Phase.clip) return;
    final t = _clipSeconds();
    final playing = _clipPlayer?.playing ?? false;
    if (blend.handedOff) {
      host.clipProgress(blend.incomingIndex, _seconds(blend.incomingAt(t)), playing);
    } else {
      host.clipProgress(blend.outgoingIndex, _seconds(blend.outgoingAt(t)), playing);
    }
  }

  bool _closing = false;

  void _driveClip() {
    final blend = _blend;
    if (blend == null || _closing) return;
    final t = _clipSeconds();
    final progress = blend.progressAt(t);
    _mixProgress = progress;
    if (!blend.handedOff && blend.handoffDue(t)) {
      blend.handedOff = true;
      host.clipHandoff(blend.inPlayer, blend.incomingIndex);
    }
    _publishClip();
    if (t >= blend.span - 0.005) {
      _closing = true;
      unawaited(_closeClip(blend, _generation).whenComplete(() => _closing = false));
    }
  }

  // ---- The closing hand-over: the clip into the spare player ------------------

  Future<void> _closeClip(_Blend blend, int generation) async {
    final clip = _clipPlayer;
    if (clip == null) return;
    bool stale() => generation != _generation;
    if (!blend.handedOff) {
      blend.handedOff = true;
      host.clipHandoff(blend.inPlayer, blend.incomingIndex);
    }
    // Where the incoming song is in the clip, on its own timeline.
    double clipIncomingTime() => blend.incomingAt(_clipSeconds());
    double spareTime() => host.positionOf(blend.inPlayer).inMicroseconds / 1e6;

    await host.setVolume(blend.inPlayer, 0);
    await host.seek(blend.inPlayer, _seconds(clipIncomingTime()));
    host.play(blend.inPlayer);
    await _waitFor(() => host.isPlaying(blend.inPlayer) && spareTime() > blend.resumeAt - 1,
        const Duration(milliseconds: 800));
    if (stale()) return;
    await _align(spareTime, clipIncomingTime, (to) => host.seek(blend.inPlayer, _seconds(to)));
    if (stale()) return;
    await _crossover(
      fadeOut: (v) => clip.setGain(v * host.masterVolume),
      fadeIn: (v) => host.setVolume(blend.inPlayer, v),
    );
    if (stale()) return;
    await _stopClip();
    _discardClip(blend.clipPath);
    await host.retire(blend.outPlayer);
    _mixing = false;
    _mixProgress = 0;
    final rate = blend.rate;
    _blend = null;
    host.clipEnded(blend.inPlayer);
    debugPrint('Automix: blend done, ${blend.incomingId} carries on');
    if ((rate - 1.0).abs() >= easeDone) {
      _beginEase(blend.inPlayer, rate, analyzer.analysisFor(blend.incomingId));
    } else {
      _phase = _Phase.idle;
    }
    _schedule();
  }

  /// Brings [measured] into step with [wanted], both in seconds of the same
  /// timeline: reads each a few times, then moves [measured]'s player once.
  Future<void> _align(double Function() measured, double Function() wanted, Future<void> Function(double) seekTo) async {
    final errors = <double>[];
    for (var i = 0; i < 5; i++) {
      errors.add(measured() - wanted());
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    errors.sort();
    final error = errors[errors.length ~/ 2];
    if (error.abs() > 0.012) {
      await seekTo(measured() - error);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  /// A short equal-power crossover between two players holding the same audio.
  Future<void> _crossover({
    required Future<void> Function(double) fadeOut,
    required Future<void> Function(double) fadeIn,
  }) async {
    const steps = 6;
    final stepMs = _crossoverTime.inMilliseconds ~/ steps;
    for (var i = 1; i <= steps; i++) {
      final x = i / steps;
      await Future.wait([fadeOut(math.cos(x * math.pi / 2)), fadeIn(math.sin(x * math.pi / 2))]);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  }

  // ---- Live blends (iOS) ---------------------------------------------------------
  //
  // BitChord-iOS's CrossfadeController: the outgoing song keeps playing on
  // its player, the incoming one starts on the spare at its cue, and each
  // tick sets both players' volumes and transition filters (the audio tap's
  // TransitionFilter) from the same automation a rendered blend bakes in.
  // Progress is read off the incoming song's position, so a pause parks the
  // blend where it stands. Nothing is rendered, so nothing has to be lined
  // up with what's already playing: no hand-over into a clip and out again.

  /// How long the incoming player takes from play() to being heard,
  /// measured on each blend (BitChord-iOS measures ~0.25 s on the tap).
  double _liveLatency = 0.25;
  BlendAutomation? _liveAutomation;
  double _liveSentIn = -1, _liveSentOut = -1;
  String _liveSentFilters = '';

  Future<void> _armLive(TransitionPlan plan, int nextIndex, String outPlayer, String inPlayer, Duration duration) async {
    final generation = ++_generation;
    _phase = _Phase.rendering;
    _endEase();
    final current = _queue[_index];
    final next = _queue[nextIndex];
    final outgoingSeconds = duration.inMilliseconds / 1000.0;
    final nextSeconds = next.durationMs / 1000.0;
    final incomingCap = nextSeconds > 0 ? math.max(0.0, nextSeconds - plan.incomingCueTime) / 3 : double.infinity;
    final span = math.max(0.05, math.min(plan.fadeSeconds, incomingCap));
    final blend = _Blend(
      plan: plan,
      render: Render.forPlan(plan),
      outgoingIndex: _index,
      incomingIndex: nextIndex,
      outgoingId: current.id,
      incomingId: next.id,
      outPlayer: outPlayer,
      inPlayer: inPlayer,
      tStart: plan.transitionStart,
      span: math.min(span, math.max(0.05, outgoingSeconds - plan.transitionStart)),
      rate: plan.incomingPlaybackRate,
      cue: plan.incomingCueTime,
      outgoingDuration: outgoingSeconds,
    )..live = true;
    _blend = blend;
    debugPrint('Automix: arming live ${current.id} -> ${next.id}: ${_styleName(plan)} '
        'at ${blend.tStart.toStringAsFixed(2)}s for ${blend.span.toStringAsFixed(2)}s, '
        'cue ${blend.cue.toStringAsFixed(2)}s @${blend.rate}x (${plan.reason})');
    bool stale() => generation != _generation;
    try {
      final loaded = await host.loadIncoming(inPlayer, nextIndex, _seconds(blend.cue));
      if (stale()) return;
      if (!loaded) throw StateError('incoming song would not load');
      await host.setSpeed(inPlayer, host.listenerSpeed * blend.rate);
      host.setTransitionFilter(inPlayer);
      if (stale()) return;
      _phase = _Phase.armed;
      _schedule();
    } catch (e) {
      debugPrint('Automix: arming failed: $e');
      _lastIssue = 'blend failed: $e';
      _failedPair = '${current.id}>${next.id}';
      if (!stale()) await _bail();
    }
  }

  void _startLive(_Blend blend) {
    _phase = _Phase.live;
    _liveAutomation = BlendAutomation(blend.render);
    _liveSentIn = _liveSentOut = -1;
    _liveSentFilters = '';
    blend.liveCue = host.positionOf(blend.inPlayer).inMicroseconds / 1e6;
    blend.liveStartedAt = DateTime.now();
    blend.latencyMeasured = false;
    _rideLive(blend, 0.0);
    host.play(blend.inPlayer);
    _mixing = blend.isRealMix;
    _windowStart = _windowEnd = null;
    _lastIssue = null;
    _schedule();
    debugPrint('Automix: live blend under way');
  }

  /// Blend seconds (outgoing time) the incoming song has played.
  double _liveSeconds(_Blend blend) {
    final position = host.positionOf(blend.inPlayer).inMicroseconds / 1e6;
    return math.max(0.0, position - blend.liveCue) / math.max(blend.rate, 0.01);
  }

  void _driveLive() {
    final blend = _blend;
    if (blend == null || _closing) return;
    final t = _liveSeconds(blend);
    if (!blend.latencyMeasured && t > 0) {
      blend.latencyMeasured = true;
      final started = blend.liveStartedAt;
      if (started != null) {
        final wall = DateTime.now().difference(started).inMicroseconds / 1e6;
        final measured = (wall - t / math.max(host.listenerSpeed, 0.01)).clamp(0.0, 0.6);
        _liveLatency = (_liveLatency + measured) / 2;
      }
    }
    // The other player follows the session's play / pause (the service
    // plays and pauses the current one).
    final session = blend.handedOff ? blend.inPlayer : blend.outPlayer;
    final other = blend.handedOff ? blend.outPlayer : blend.inPlayer;
    final wanted = host.wantsToPlay(session);
    if (wanted != host.wantsToPlay(other)) {
      if (wanted) {
        host.play(other);
      } else {
        unawaited(host.pause(other));
      }
    }
    // By time, or by how little of the outgoing song is left (read off its
    // player: after a seek onto the marker it isn't where the plan began).
    final outPosition = host.positionOf(blend.outPlayer).inMicroseconds / 1e6;
    final byEnd = (blend.span - (blend.outgoingDuration - outPosition)) / blend.span;
    final progress = math.max(t / blend.span, byEnd).clamp(0.0, 1.0);
    _mixProgress = progress;
    _rideLive(blend, progress);
    if (!blend.handedOff && progress >= blend.render.handoffAt) {
      blend.handedOff = true;
      host.liveHandoff(blend.inPlayer, blend.incomingIndex);
    }
    final outEnded = outPosition >= blend.outgoingDuration - 0.05;
    if (progress >= 1.0 || outEnded) {
      _closing = true;
      unawaited(_finishLive(blend, _generation).whenComplete(() => _closing = false));
    }
  }

  /// Both players' faders and filters at [progress].
  void _rideLive(_Blend blend, double progress) {
    final automation = _liveAutomation ??= BlendAutomation(blend.render);
    final wallSpanMs = blend.span * 1000;
    final frame = automation.at(progress, wallSpanMs);
    final headroom = BlendAutomation.headroomFor(
        automation.mixRise(progress), automation.outgoingLevel(progress, wallSpanMs));
    final echo = blend.render.echo && frame.echoEngaged;
    final inGain = (frame.inGain * headroom).clamp(0.0, 1.0);
    final outGain = ((progress >= 1.0 && !echo ? 0.0 : frame.outGain) * headroom).clamp(0.0, 1.0);
    if ((inGain - _liveSentIn).abs() > 0.002) {
      _liveSentIn = inGain;
      unawaited(host.setVolume(blend.inPlayer, inGain));
    }
    if ((outGain - _liveSentOut).abs() > 0.002) {
      _liveSentOut = outGain;
      unawaited(host.setVolume(blend.outPlayer, outGain));
    }
    final filters = '${frame.inLow.round()}|${frame.inHigh.round()}|${frame.outLow.round()}|'
        '${frame.outHigh.round()}|$echo|${frame.echoSend.toStringAsFixed(2)}|${frame.echoDry.toStringAsFixed(2)}';
    if (filters == _liveSentFilters) return;
    _liveSentFilters = filters;
    host.setTransitionFilter(blend.inPlayer, lowPassHz: frame.inLow, highPassHz: frame.inHigh);
    host.setTransitionFilter(blend.outPlayer,
        lowPassHz: frame.outLow,
        highPassHz: frame.outHigh,
        echoSeconds: echo ? blend.render.echoSeconds : 0,
        echoSend: echo ? frame.echoSend : 0,
        echoDry: echo ? frame.echoDry : 1);
  }

  /// The blend has run its course: the incoming song carries on alone.
  Future<void> _finishLive(_Blend blend, int generation) async {
    if (!blend.handedOff) {
      blend.handedOff = true;
      host.liveHandoff(blend.inPlayer, blend.incomingIndex);
    }
    final echo = blend.render.echo;
    host.setTransitionFilter(blend.inPlayer);
    await host.setVolume(blend.inPlayer, 1.0);
    if (generation != _generation) return;
    _mixing = false;
    _mixProgress = 0;
    _blend = null;
    _liveAutomation = null;
    final rate = blend.rate;
    if ((rate - 1.0).abs() >= easeDone) {
      _beginEase(blend.inPlayer, rate, analyzer.analysisFor(blend.incomingId));
    } else {
      _phase = _Phase.idle;
    }
    _schedule();
    debugPrint('Automix: live blend done, ${blend.incomingId} carries on');
    // An echo out rings on a moment after its source has stopped.
    if (echo) await Future<void>.delayed(const Duration(milliseconds: 1500));
    host.setTransitionFilter(blend.outPlayer);
    await host.retire(blend.outPlayer);
  }

  /// A skip, seek or switch-off mid-blend: whichever song is current
  /// carries on at full volume, unfiltered, at the listener's speed.
  Future<void> _leaveLive() async {
    final blend = _blend;
    _generation++;
    _phase = _Phase.idle;
    _mixing = false;
    _mixProgress = 0;
    _blend = null;
    _liveAutomation = null;
    if (blend == null) return;
    final session = blend.handedOff ? blend.inPlayer : blend.outPlayer;
    final other = blend.handedOff ? blend.outPlayer : blend.inPlayer;
    host.setTransitionFilter(session);
    host.setTransitionFilter(other);
    await host.setVolume(session, 1.0);
    await host.setSpeed(session, host.listenerSpeed);
    await host.retire(other);
    _schedule();
  }

  // ---- Tempo ease-back -----------------------------------------------------------

  void _beginEase(String player, double rate, TrackAnalysis analysis) {
    final steps = rampStepsFor(rate);
    final beat = analysis.beatInterval > 0
        ? analysis.beatInterval
        : (analysis.bpm > 0 ? 60.0 / analysis.bpm : 0.0);
    _easePlayer = player;
    _easeRate = rate;
    _easeStep = (rate - 1.0) / steps;
    _easeStepMs = beat > 0 ? (beat * 1000).round() : 500;
    _easeNextAtMs = host.positionOf(player).inMilliseconds + _easeStepMs;
    _phase = _Phase.easing;
  }

  void _driveEase() {
    final player = _easePlayer;
    if (player == null || player != _active) {
      _endEase();
      return;
    }
    final position = host.positionOf(player).inMilliseconds;
    if (position < _easeNextAtMs - 2 * _easeStepMs) {
      _endEase();
      return;
    }
    if (position < _easeNextAtMs) return;
    _easeRate -= _easeStep;
    if ((_easeRate - 1.0).abs() < easeDone) {
      _endEase();
      return;
    }
    unawaited(host.setSpeed(player, host.listenerSpeed * _easeRate));
    _easeNextAtMs += _easeStepMs;
  }

  void _endEase() {
    final player = _easePlayer;
    _easePlayer = null;
    if (player != null) unawaited(host.setSpeed(player, host.listenerSpeed));
    if (_phase == _Phase.easing) _phase = _Phase.idle;
  }

  // ---- Giving up -------------------------------------------------------------------

  /// Drops whatever blend is in flight; the song carries on plainly.
  Future<void> _abort(String why) async {
    if (_phase == _Phase.live) {
      debugPrint('Automix: leaving the live blend ($why)');
      await _leaveLive();
      return;
    }
    if (_phase == _Phase.clip) {
      debugPrint('Automix: leaving the blend ($why)');
      await leaveClip();
      return;
    }
    if (_phase == _Phase.rendering || _phase == _Phase.armed) {
      debugPrint('Automix: dropping the armed blend ($why)');
      await _bail();
    }
    if (_phase == _Phase.easing) _endEase();
  }

  Future<void> _bail() async {
    _generation++;
    final blend = _blend;
    _blend = null;
    _phase = _Phase.idle;
    _mixing = false;
    if (blend != null) {
      await host.retire(blend.inPlayer);
    }
    await _stopClip();
    _discardClip(blend?.clipPath);
    _schedule();
  }

  Future<void> _stopClip() async {
    final clip = _clipPlayer;
    if (clip == null) return;
    try {
      await clip.setGain(0);
      await clip.stop();
    } catch (_) {}
  }

  static Future<void> _waitFor(bool Function() condition, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  static Duration _seconds(double seconds) => Duration(microseconds: (seconds * 1e6).round());

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Seconds since the last beat and the beat's length at [position] on
  /// [analysis]'s grid (CrossfadeController.beatAt).
  static (double, double)? _beatAt(TrackAnalysis analysis, double position) {
    final fromTempo = analysis.bpm > 0 ? 60.0 / analysis.bpm : 0.0;
    final interval = analysis.beatInterval;
    final double nominal;
    if (interval > 0 && (fromTempo <= 0 || (interval / fromTempo - 1).abs() < 0.25)) {
      nominal = interval;
    } else if (fromTempo > 0) {
      nominal = fromTempo;
    } else {
      return null;
    }
    final downbeats = analysis.downbeats;
    var next = 0;
    while (next < downbeats.length && downbeats[next] <= position) {
      next++;
    }
    double origin;
    var beat = nominal;
    if (next >= 1 && next < downbeats.length) {
      origin = downbeats[next - 1];
      final bar = downbeats[next] - origin;
      final beatsInBar = (bar / nominal).round();
      if (beatsInBar >= 1 && beatsInBar <= 8) beat = bar / beatsInBar;
    } else {
      origin = next >= 1 ? downbeats[next - 1] : analysis.firstBeat;
    }
    if (beat <= 0 || !beat.isFinite) return null;
    return (((position - origin) % beat + beat) % beat, beat);
  }
}

// ---- The render, in its own isolate --------------------------------------------------

class _RenderJob {
  const _RenderJob({
    required this.outUri,
    required this.outHeaders,
    required this.inUri,
    required this.inHeaders,
    required this.tStart,
    required this.cue,
    required this.rate,
    required this.span,
    required this.clipSeconds,
    required this.outgoingDuration,
    required this.plan,
    required this.scratch,
    required this.clipPath,
    this.outCopy,
    this.inCopy,
    this.outLevel = 1.0,
    this.inLevel = 1.0,
  });
  /// Loudness normalization's gain for each side.
  final double outLevel;
  final double inLevel;
  /// The files each song was analysed from, to measure the sources against.
  final String? outCopy;
  final String? inCopy;
  final String outUri;
  final Map<String, String> outHeaders;
  final String inUri;
  final Map<String, String> inHeaders;
  final double tStart;
  final double cue;
  final double rate;
  final double span;
  final double clipSeconds;
  final double outgoingDuration;
  final TransitionPlan plan;
  final String scratch;
  final String clipPath;
}

String _decodable(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed != null && parsed.isScheme('file')) return parsed.toFilePath();
  return uri;
}

typedef _RenderResult = ({bool ok, String report, double offOut, double offIn});

/// Top level, so the isolate's closure carries the job and nothing else.
Future<_RenderResult> _renderOffThread(_RenderJob job) => Isolate.run(() => _renderInIsolate(job));

_RenderResult _failed(String why) => (ok: false, report: why, offOut: 0.0, offIn: 0.0);

/// Where [source] runs relative to [copy], both decoded from the same
/// nominal second, mono: in seconds (positive: the source is later), or 0
/// when the two don't line up well enough to trust (a different master).
double _sourceOffset(Float32List copy, Float32List source, int rate) {
  const decimate = 8;
  Float32List down(Float32List x) {
    final out = Float32List(x.length ~/ decimate);
    for (var i = 0; i < out.length; i++) {
      var sum = 0.0;
      for (var j = 0; j < decimate; j++) {
        sum += x[i * decimate + j];
      }
      out[i] = sum / decimate;
    }
    return out;
  }

  double corr(Float32List a, Float32List b, int from, int length, int lag, int stride) {
    var num = 0.0, ea = 0.0, eb = 0.0;
    for (var i = from; i < from + length; i += stride) {
      final j = i + lag;
      if (j < 0 || j >= b.length || i >= a.length) continue;
      num += a[i] * b[j];
      ea += a[i] * a[i];
      eb += b[j] * b[j];
    }
    final den = math.sqrt(ea * eb);
    return den > 0 ? num / den : 0.0;
  }

  // Coarse at an eighth of the rate over +-250 ms, then exact around it.
  final c = down(copy), s = down(source);
  final coarseRate = rate ~/ decimate;
  final from = coarseRate ~/ 2, length = coarseRate;
  final reach = coarseRate ~/ 4;
  if (c.length < from + length || s.length < from + length + reach) return 0.0;
  var best = 0;
  var bestCorr = -1.0;
  for (var lag = -reach; lag <= reach; lag++) {
    final r = corr(c, s, from, length, lag, 1);
    if (r > bestCorr) {
      bestCorr = r;
      best = lag;
    }
  }
  if (bestCorr < 0.6) return 0.0;
  var fine = best * decimate;
  var fineCorr = -1.0;
  for (var lag = best * decimate - decimate; lag <= best * decimate + decimate; lag++) {
    final r = corr(copy, source, rate ~/ 2, rate, lag, 2);
    if (r > fineCorr) {
      fineCorr = r;
      fine = lag;
    }
  }
  return fine / rate;
}

/// The offset of [uri]'s audio against the analysis [copy] around [second].
double _measureOffset(
    PcmDecoder decoder, _RenderJob job, String? copy, String uri, double second, Map<String, String> headers) {
  if (copy == null || copy == uri || !File(copy).existsSync()) return 0.0;
  final from = math.max(0.0, second - 1.0);
  final a = decoder.decode(copy,
      scratch: job.scratch, start: from, end: from + 2.5, sampleRate: _renderRate, channels: 1);
  final b = decoder.decode(uri,
      scratch: job.scratch, start: from, end: from + 2.5, sampleRate: _renderRate, channels: 1, headers: headers);
  if (a == null || b == null) return 0.0;
  return _sourceOffset(a.samples, b.samples, _renderRate);
}

/// Decodes both sides, measures them against their analysis copies, and
/// renders the blend.
_RenderResult _renderInIsolate(_RenderJob job) {
  final decoder = PcmDecoder.instance;
  if (decoder == null || AutomixNative.instance == null) return _failed('native library missing');
  final offOut = _measureOffset(decoder, job, job.outCopy, _decodable(job.outUri), job.tStart, job.outHeaders);
  final offIn = _measureOffset(decoder, job, job.inCopy, _decodable(job.inUri), job.cue, job.inHeaders);

  // Each side with a second of pre-roll, so a stretched deck has settled
  // before it's heard and the filters have history.
  final outFrom = math.max(0.0, job.tStart - _prerollSeconds);
  final outgoing = decoder.decode(_decodable(job.outUri),
      scratch: job.scratch,
      start: outFrom,
      end: job.tStart + job.clipSeconds + 0.5,
      sampleRate: _renderRate,
      headers: job.outHeaders);
  if (outgoing == null || outgoing.frames < _renderRate * 0.5) {
    return _failed('outgoing would not decode from ${job.outUri}');
  }
  final inFrom = math.max(0.0, job.cue - _prerollSeconds);
  final incoming = decoder.decode(_decodable(job.inUri),
      scratch: job.scratch,
      start: inFrom,
      end: job.cue + job.clipSeconds * job.rate + 1.0,
      sampleRate: _renderRate,
      headers: job.inHeaders);
  if (incoming == null || incoming.frames < _renderRate * 0.5) {
    return _failed('incoming would not decode from ${job.inUri}');
  }

  final render = Render.forPlan(job.plan);
  final automation = BlendAutomation(render);
  final count = (job.clipSeconds / _envelopeStep).ceil() + 2;
  final env = BlendEnvelopes(_envelopeStep, count);
  final wallSpanMs = job.span * 1000;
  for (var i = 0; i < count; i++) {
    final t = i * _envelopeStep;
    final byTime = t / job.span;
    final outRemaining = job.outgoingDuration - job.tStart - t;
    final progress = math.max(byTime, (job.span - outRemaining) / job.span).clamp(0.0, 1.0);
    final frame = automation.at(progress, wallSpanMs);
    env.inGain[i] = frame.inGain;
    env.outGain[i] = progress >= 1.0 && !render.echo ? 0.0 : frame.outGain;
    env.inLow[i] = frame.inLow;
    env.inHigh[i] = frame.inHigh;
    env.outLow[i] = frame.outLow;
    env.outHigh[i] = frame.outHigh;
    env.echoSend[i] = frame.echoEngaged ? frame.echoSend : 0.0;
    env.echoDry[i] = frame.echoEngaged ? frame.echoDry : 1.0;
    if (frame.echoEngaged) env.echo = true;
    env.headroom[i] = BlendAutomation.headroomFor(
        automation.mixRise(progress), automation.outgoingLevel(progress, wallSpanMs));
  }

  final rendered = renderBlend(
    path: job.clipPath,
    sampleRate: _renderRate,
    frames: (job.clipSeconds * _renderRate).round(),
    envelopeStep: _envelopeStep,
    outgoing: BlendDeckInput(
      left: outgoing.channel(0),
      right: outgoing.channel(1),
      startSample: (job.tStart + offOut - outFrom) * _renderRate,
      rate: 1.0,
      stopAt: render.echo ? job.clipSeconds : job.span + 0.05,
      level: job.outLevel,
      echoSeconds: render.echo ? render.echoSeconds : 0.0,
      gain: env.outGain,
      lowPassHz: env.outLow,
      highPassHz: env.outHigh,
      echoSend: env.echo ? env.echoSend : null,
      echoDry: env.echo ? env.echoDry : null,
    ),
    incoming: BlendDeckInput(
      left: incoming.channel(0),
      right: incoming.channel(1),
      startSample: (job.cue + offIn - inFrom) * _renderRate,
      rate: job.rate,
      level: job.inLevel,
      gain: env.inGain,
      lowPassHz: env.inLow,
      highPassHz: env.inHigh,
    ),
    headroom: env.headroom,
  );
  if (!rendered) return _failed('render failed');
  String ms(double seconds) => '${(seconds * 1000).toStringAsFixed(1)}ms';
  return (
    ok: true,
    report: 'out ${p.basename(_decodable(job.outUri))} (${ms(offOut)} off its analysis copy), '
        'in ${p.basename(_decodable(job.inUri))} (${ms(offIn)})',
    offOut: offOut,
    offIn: offIn,
  );
}

/// Where desktop keeps Automix's analyses between runs.
String automixStoreDir(String appData) => p.join(appData, 'automix_analysis');

// ---- The loop mix render, in its own isolate ----------------------------------------

class _LoopJob {
  const _LoopJob({
    required this.outUri,
    required this.outHeaders,
    required this.inUri,
    required this.inHeaders,
    required this.plan,
    required this.clipSeconds,
    required this.scratch,
    required this.clipPath,
    this.outLevel = 1.0,
    this.inLevel = 1.0,
  });
  final String outUri;
  final Map<String, String> outHeaders;
  final String inUri;
  final Map<String, String> inHeaders;
  /// Loudness normalization's gain for each side.
  final double outLevel;
  final double inLevel;
  final LoopMixPlan plan;
  final double clipSeconds;
  final String scratch;
  final String clipPath;
}

/// Null when the clip was written, otherwise why not.
Future<String?> _renderLoopOffThread(_LoopJob job) => Isolate.run(() => _renderLoopInIsolate(job));

/// LoopMixSession.build, decoding with libmpv and writing the mix to a file
/// instead of handing it to the sinks.
String? _renderLoopInIsolate(_LoopJob job) {
  final decoder = PcmDecoder.instance;
  if (decoder == null || AutomixNative.instance == null) return 'native library missing';
  final plan = job.plan;
  final clock = LoopMixClock(plan);
  const sr = _renderRate;
  const preroll = 1.0;
  const tail = 3.0;
  final outFrom = math.max(0.0, plan.out.loopStart - preroll);
  final outRegion = decoder.decode(_decodable(job.outUri),
      scratch: job.scratch, start: outFrom, end: plan.out.loopEnd + 0.5, sampleRate: sr, headers: job.outHeaders);
  if (outRegion == null || outRegion.frames < sr) return 'the outgoing loop would not decode';
  final inFrom = math.max(0.0, plan.inn.loopStart - preroll);
  final inRegion = decoder.decode(_decodable(job.inUri),
      scratch: job.scratch,
      start: inFrom,
      end: clock.elementTrackTime + tail,
      sampleRate: sr,
      headers: job.inHeaders);
  if (inRegion == null || inRegion.frames < sr) return 'the incoming loop would not decode';

  double samplesOf(double regionStart, double trackSeconds) => (trackSeconds - regionStart) * sr;
  final beats = clock.beats;
  final knotFrames = Float64List.fromList([for (var k = 0; k <= beats; k++) clock.beatTimes[k] * sr]);
  final outKnots = Float64List.fromList([for (var k = 0; k <= beats; k++) samplesOf(outFrom, clock.outPositionAt(k))]);
  final inKnots = Float64List.fromList([for (var k = 0; k <= beats; k++) samplesOf(inFrom, clock.inPositionAt(k))]);
  const h = LoopMix.handoverSec;
  final swapFrom = clock.handoffAt - clock.swapBar / 2;
  final swapTo = clock.handoffAt + clock.swapBar / 2;
  const cut = LoopMix.bassCutDb;
  final ok = renderLoopMix(
    path: job.clipPath,
    sampleRate: sr,
    frames: (job.clipSeconds * sr).round(),
    outgoing: LoopDeckInput(
      left: outRegion.channel(0),
      right: outRegion.channel(1),
      regionStart: outFrom,
      loopStart: samplesOf(outFrom, plan.out.loopStart).round(),
      loopEnd: samplesOf(outFrom, plan.out.loopEnd).round(),
      releaseAt: 1e18,
      knotFrames: knotFrames,
      knotPositions: outKnots,
      runOn: false,
      stopAt: clock.releaseAt + 0.05,
      level: job.outLevel,
    ),
    incoming: LoopDeckInput(
      left: inRegion.channel(0),
      right: inRegion.channel(1),
      regionStart: inFrom,
      loopStart: samplesOf(inFrom, plan.inn.loopStart).round(),
      loopEnd: samplesOf(inFrom, plan.inn.loopEnd).round(),
      releaseAt: samplesOf(inFrom, clock.inReleasePosition),
      knotFrames: knotFrames,
      knotPositions: inKnots,
      runOn: true,
      // Runs on past the hand-over: the spare player takes over from the
      // clip with a crossover of its own rather than the deck fading out.
      stopAt: clock.elementAt + 2.0,
      level: job.inLevel,
    ),
    envelopes: [
      LoopEnvelope(0, LoopEnvelope.gain, [-h, 0.0, clock.enterEnd, clock.rampEnd, clock.releaseAt],
          [0, 1, 1, 0.6, 0]),
      LoopEnvelope(1, LoopEnvelope.gain, [0.0, clock.enterEnd, clock.rampEnd], [0, 0.55, 1]),
      LoopEnvelope(0, LoopEnvelope.lowDb, [swapFrom, swapTo], [0, cut]),
      LoopEnvelope(1, LoopEnvelope.lowDb, [swapFrom, swapTo], [cut, 0]),
      LoopEnvelope(0, LoopEnvelope.highPassHz, [clock.rampEnd, clock.releaseAt],
          [LoopMix.highPassFromHz, LoopMix.highPassToHz],
          exponential: true),
    ],
  );
  return ok ? null : 'the loop mix would not render';
}
