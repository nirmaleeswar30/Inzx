import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'audio_player_service.dart';

/// The stretch of listening a summary covers.
enum StatsPeriod { week, month, year, allTime }

/// One song's share of a period.
class TrackStat {
  const TrackStat(this.track, this.plays, this.ms);
  final Track track;
  final int plays;
  final int ms;
}

/// One artist's share of a period. [imageUrl] is the cover of their most
/// listened song, which is the best picture of them there is offline.
class ArtistStat {
  const ArtistStat({
    required this.name,
    required this.artistId,
    required this.plays,
    required this.ms,
    required this.imageUrl,
  });
  final String name;
  final String? artistId;
  final int plays;
  final int ms;
  final String? imageUrl;
}

/// One album's share of a period.
class AlbumStat {
  const AlbumStat({
    required this.name,
    required this.albumId,
    required this.artist,
    required this.plays,
    required this.ms,
    required this.imageUrl,
  });
  final String name;
  final String? albumId;
  final String artist;
  final int plays;
  final int ms;
  final String? imageUrl;
}

/// One bar of the activity chart: a day, or a month for longer periods.
class StatsBucket {
  const StatsBucket({
    required this.start,
    required this.ms,
    required this.isCurrent,
    required this.isMonth,
  });
  final DateTime start;
  final int ms;

  /// Today, or this month.
  final bool isCurrent;
  final bool isMonth;
}

/// Everything the statistics page, the Home shelf and the Library tab show
/// for one [period].
class ListeningSummary {
  ListeningSummary({
    required this.period,
    required this.totalMs,
    required this.plays,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.previousTotalMs,
    required this.buckets,
    required this.hourly,
    required this.weekday,
    required this.topTracks,
    required this.topArtists,
    required this.topAlbums,
    required this.newTracks,
    required this.activeDays,
    required this.days,
    required this.currentStreak,
    required this.longestStreak,
    required this.busiestDay,
    required this.busiestDayMs,
    required this.firstDay,
  });

  final StatsPeriod period;
  final int totalMs;
  final int plays;
  final int uniqueTracks;
  final int uniqueArtists;

  /// The same length of time just before; null for all time.
  final int? previousTotalMs;
  final List<StatsBucket> buckets;

  /// Listening per hour of the day, local time, 0 = midnight.
  final List<int> hourly;

  /// Listening per day of the week, 0 = Monday.
  final List<int> weekday;
  final List<TrackStat> topTracks;
  final List<ArtistStat> topArtists;
  final List<AlbumStat> topAlbums;

  /// Songs first heard in this period.
  final int newTracks;

  /// Days in the period with any listening, and the period's length in days.
  final int activeDays;
  final int days;
  final int currentStreak;
  final int longestStreak;
  final DateTime? busiestDay;
  final int busiestDayMs;

  /// The first day anything was recorded.
  final DateTime? firstDay;

  bool get isEmpty => totalMs == 0 && plays == 0;

  /// Change against the previous period, as a fraction (0.25 = +25 %), or
  /// null when there's nothing to compare with.
  double? get change {
    final previous = previousTotalMs;
    if (previous == null || previous < 60000) return null;
    return (totalMs - previous) / previous;
  }

  /// The hour with the most listening, or null with none.
  int? get peakHour => _peak(hourly);

  /// The weekday (0 = Monday) with the most listening, or null with none.
  int? get peakWeekday => _peak(weekday);

  static int? _peak(List<int> values) {
    var best = -1;
    var bestValue = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > bestValue) {
        best = i;
        bestValue = values[i];
      }
    }
    return best < 0 ? null : best;
  }
}

/// What one day of listening holds.
class _Day {
  _Day();

  int ms = 0;
  int plays = 0;
  final List<int> hours = List<int>.filled(24, 0);

  /// trackId -> [plays, ms]
  final Map<String, List<int>> tracks = {};

  Map<String, dynamic> toJson() => {
    'ms': ms,
    'p': plays,
    'h': hours,
    't': tracks,
  };

  static _Day fromJson(Map json) {
    final day = _Day()
      ..ms = (json['ms'] as num?)?.toInt() ?? 0
      ..plays = (json['p'] as num?)?.toInt() ?? 0;
    final hours = json['h'];
    if (hours is List) {
      for (var i = 0; i < 24 && i < hours.length; i++) {
        day.hours[i] = (hours[i] as num?)?.toInt() ?? 0;
      }
    }
    final tracks = json['t'];
    if (tracks is Map) {
      tracks.forEach((key, value) {
        if (value is List && value.length >= 2) {
          day.tracks[key.toString()] = [
            (value[0] as num).toInt(),
            (value[1] as num).toInt(),
          ];
        }
      });
    }
    return day;
  }
}

/// Listening statistics: follows the player, keeps a log per day of how
/// long you actually listened (paused and buffering time don't count), and
/// sums it up for any period.
///
/// A song counts as a play once it has been listened to for 30 seconds, or
/// half its length if it's shorter, so skips aren't counted. Time is
/// recorded either way.
///
/// The log lives in its own Hive box: one entry per day (time per hour, and
/// plays and time per song), one per song (what it is and when it was first
/// heard), and the totals carried over from the old play counter, which had
/// no dates.
class ListeningStatsService extends ChangeNotifier with WidgetsBindingObserver {
  ListeningStatsService._();

  static final instance = ListeningStatsService._();

  static const _boxName = 'listening_stats';
  static const _legacyPrefsKey = 'play_statistics';

  /// Time is written out at least this often while something plays, so a
  /// crash loses little and each minute lands in the right hour.
  static const _flushEvery = Duration(seconds: 15);
  static const _playThreshold = Duration(seconds: 30);

  Box<dynamic>? _box;
  final Map<int, _Day> _days = {};
  final Map<String, Track> _tracks = {};
  final Map<String, int> _firstHeard = {};
  final Map<String, List<int>> _legacy = {};
  final Set<int> _dirtyDays = {};
  final Set<String> _dirtyTracks = {};

  StreamSubscription<PlaybackState>? _sub;
  Timer? _timer;
  Track? _song;
  Duration _songListened = Duration.zero;
  Duration _songLength = Duration.zero;
  bool _songCounted = false;
  DateTime? _playingSince;
  Future<void>? _starting;
  bool _ready = false;

  bool get isReady => _ready;

  /// Opens the log and starts following the player. Safe to call again.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      _load();
      await _migrateLegacy();
    } catch (e) {
      debugPrint('ListeningStats: unavailable: $e');
      return;
    }
    _ready = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = AudioPlayerService.instance.stateStream.listen(_onState);
    notifyListeners();
  }

  void _load() {
    final box = _box!;
    for (final key in box.keys) {
      final name = key.toString();
      final value = box.get(key);
      if (value is! Map) continue;
      if (name.startsWith('d')) {
        final day = int.tryParse(name.substring(1));
        if (day != null) _days[day] = _Day.fromJson(value);
      } else if (name.startsWith('m')) {
        final id = name.substring(1);
        try {
          _tracks[id] = Track.fromJson(
            Map<String, dynamic>.from(value['track'] as Map),
          );
          final first = (value['f'] as num?)?.toInt();
          if (first != null) _firstHeard[id] = first;
        } catch (_) {}
      } else if (name == 'legacy') {
        value.forEach((id, entry) {
          if (entry is List && entry.length >= 2) {
            _legacy[id.toString()] = [
              (entry[0] as num).toInt(),
              (entry[1] as num).toInt(),
            ];
          }
        });
      }
    }
  }

  /// The old counter kept all-time plays per song, without dates. They're
  /// kept as all-time totals, so nobody's history starts from zero.
  Future<void> _migrateLegacy() async {
    final box = _box!;
    if (box.get('legacy_migrated') == true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_legacyPrefsKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        map.forEach((id, raw) {
          if (raw is! Map) return;
          final plays = (raw['playCount'] as num?)?.toInt() ?? 0;
          final ms = (raw['totalPlayTimeMs'] as num?)?.toInt() ?? 0;
          if (plays <= 0) return;
          _legacy[id] = [plays, ms];
          _tracks.putIfAbsent(
            id,
            () => Track(
              id: id,
              title: raw['title']?.toString() ?? 'Unknown',
              artist: raw['artist']?.toString() ?? 'Unknown artist',
              duration: Duration.zero,
              thumbnailUrl: raw['thumbnailUrl']?.toString(),
            ),
          );
          _dirtyTracks.add(id);
        });
        await box.put('legacy', _legacy);
        await prefs.remove(_legacyPrefsKey);
      }
    } catch (e) {
      debugPrint('ListeningStats: old counts not carried over: $e');
    }
    await box.put('legacy_migrated', true);
    await _persist();
  }

  // ---- Following the player -------------------------------------------

  void _onState(PlaybackState state) {
    final track = state.currentTrack;
    if (track?.id != _song?.id) {
      _flush();
      _song = track;
      _songListened = Duration.zero;
      _songLength = Duration.zero;
      _songCounted = false;
      _playingSince = null;
    }
    // The player's length is the reliable one; it can arrive a moment after
    // the song does.
    final length = state.duration ?? track?.duration;
    if (length != null && length > Duration.zero) _songLength = length;
    final playing =
        track != null &&
        state.isPlaying &&
        !state.isBuffering &&
        !state.isLoading &&
        !(state.currentPlaybackData?.isLive ?? false);
    if (playing && _playingSince == null) {
      _playingSince = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(_flushEvery, (_) => _flush());
    } else if (!playing && _playingSince != null) {
      _flush();
      _playingSince = null;
      _timer?.cancel();
    }
    if (track != null) _rememberTrack(track);
  }

  /// Books the time played since the last flush onto today, and counts the
  /// song as played once it has been heard long enough.
  void _flush() {
    final since = _playingSince;
    final song = _song;
    if (since == null || song == null) return;
    final now = DateTime.now();
    var elapsed = now.difference(since);
    _playingSince = now;
    if (elapsed <= Duration.zero) return;
    // A long gap means the app was asleep, not playing.
    if (elapsed > _flushEvery * 4) elapsed = _flushEvery;
    final ms = elapsed.inMilliseconds;

    final key = _dayKey(now);
    final day = _days.putIfAbsent(key, _Day.new);
    day.ms += ms;
    day.hours[now.hour] += ms;
    final entry = day.tracks.putIfAbsent(song.id, () => [0, 0]);
    entry[1] += ms;
    _songListened += elapsed;

    if (!_songCounted && _songListened >= _threshold()) {
      _songCounted = true;
      day.plays += 1;
      entry[0] += 1;
    }
    _rememberTrack(song, firstHeard: key);
    _dirtyDays.add(key);
    unawaited(_persist());
    notifyListeners();
  }

  Duration _threshold() {
    final length = _songLength;
    if (length <= Duration.zero) return _playThreshold;
    final half = length ~/ 2;
    return half < _playThreshold ? half : _playThreshold;
  }

  void _rememberTrack(Track track, {int? firstHeard}) {
    final known = _tracks[track.id];
    // Keep the richest copy: later ones carry the length and album.
    if (known == null ||
        (known.duration == Duration.zero && track.duration > Duration.zero) ||
        (known.album == null && track.album != null) ||
        (known.thumbnailUrl == null && track.thumbnailUrl != null)) {
      _tracks[track.id] = track;
      _dirtyTracks.add(track.id);
    }
    if (firstHeard != null && !_firstHeard.containsKey(track.id)) {
      _firstHeard[track.id] = firstHeard;
      _dirtyTracks.add(track.id);
    }
  }

  Future<void>? _writing;

  Future<void> _persist() {
    return _writing = (_writing ?? Future<void>.value()).then((_) async {
      final box = _box;
      if (box == null) return;
      final days = _dirtyDays.toList();
      final tracks = _dirtyTracks.toList();
      _dirtyDays.clear();
      _dirtyTracks.clear();
      final entries = <String, dynamic>{
        for (final key in days)
          if (_days[key] case final day?) 'd$key': day.toJson(),
        for (final id in tracks)
          if (_tracks[id] case final track?)
            'm$id': {
              'track': _storable(track),
              if (_firstHeard[id] case final first?) 'f': first,
            },
      };
      if (entries.isNotEmpty) await box.putAll(entries);
    }).catchError((Object e) => debugPrint('ListeningStats: save failed: $e'));
  }

  /// A song as stored: everything needed to play it again from the stats.
  static Map<String, dynamic> _storable(Track track) {
    final json = track.toJson();
    json.remove('isLiked');
    json.remove('addedAt');
    return json;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flush();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Records [ms] of [track] at [at], and a play with [countPlay], straight
  /// into memory: no player, no box.
  @visibleForTesting
  void debugRecord(
    Track track, {
    required DateTime at,
    required int ms,
    bool countPlay = true,
  }) {
    final key = _dayKey(at);
    final day = _days.putIfAbsent(key, _Day.new);
    day.ms += ms;
    day.hours[at.hour] += ms;
    final entry = day.tracks.putIfAbsent(track.id, () => [0, 0]);
    entry[1] += ms;
    if (countPlay) {
      day.plays += 1;
      entry[0] += 1;
    }
    _tracks[track.id] = track;
    _firstHeard.putIfAbsent(track.id, () => key);
  }

  /// Adds dateless all-time totals, as carried over from the old counter.
  @visibleForTesting
  void debugLegacy(Track track, {required int plays, required int ms}) {
    _legacy[track.id] = [plays, ms];
    _tracks.putIfAbsent(track.id, () => track);
  }

  @visibleForTesting
  void debugReset() {
    _days.clear();
    _tracks.clear();
    _firstHeard.clear();
    _legacy.clear();
  }

  /// Everything recorded, for a backup: plain JSON values only.
  Map<String, dynamic> export() {
    _flush();
    final box = _box;
    if (box == null) return const {};
    return {
      for (final key in box.keys)
        if (box.get(key) case final value?) key.toString(): value,
    };
  }

  /// Replaces what's recorded with a backup's [data] (see [export]).
  Future<void> restore(Map<String, dynamic> data) async {
    final box = _box;
    if (box == null) return;
    await box.clear();
    await box.putAll(data);
    _days.clear();
    _tracks.clear();
    _firstHeard.clear();
    _legacy.clear();
    _load();
    await box.put('legacy_migrated', true);
    notifyListeners();
  }

  /// Forgets everything recorded so far.
  Future<void> clear() async {
    _days.clear();
    _tracks.clear();
    _firstHeard.clear();
    _legacy.clear();
    _dirtyDays.clear();
    _dirtyTracks.clear();
    _songListened = Duration.zero;
    _songCounted = true; // the song playing now doesn't count again
    final box = _box;
    if (box != null) {
      await box.clear();
      await box.put('legacy_migrated', true);
    }
    notifyListeners();
  }

  // ---- Summaries --------------------------------------------------------

  static int _dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

  static DateTime _dateOf(int key) =>
      DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The most played songs of all time, to play as a mix.
  List<Track> mostPlayed({int limit = 50}) =>
      summarize(StatsPeriod.allTime, limit: limit)
          .topTracks
          .map((t) => t.track)
          .toList();

  /// Sums up [period], ending today.
  ListeningSummary summarize(StatsPeriod period, {int limit = 50}) {
    final today = _today();
    final firstKey = _days.isEmpty
        ? null
        : _days.keys.reduce((a, b) => a < b ? a : b);
    final firstDay = firstKey == null ? null : _dateOf(firstKey);

    final DateTime start;
    switch (period) {
      case StatsPeriod.week:
        start = today.subtract(const Duration(days: 6));
      case StatsPeriod.month:
        start = today.subtract(const Duration(days: 29));
      case StatsPeriod.year:
        start = DateTime(today.year - 1, today.month + 1, 1);
      case StatsPeriod.allTime:
        start = firstDay ?? today;
    }
    final startKey = _dayKey(start);
    final todayKey = _dayKey(today);
    final days = today.difference(start).inDays + 1;

    var totalMs = 0;
    var plays = 0;
    var activeDays = 0;
    final hourly = List<int>.filled(24, 0);
    final weekday = List<int>.filled(7, 0);
    final perTrack = <String, List<int>>{};
    DateTime? busiestDay;
    var busiestMs = 0;

    for (final entry in _days.entries) {
      if (entry.key < startKey || entry.key > todayKey) continue;
      final day = entry.value;
      if (day.ms <= 0 && day.plays <= 0) continue;
      final date = _dateOf(entry.key);
      totalMs += day.ms;
      plays += day.plays;
      if (day.ms > 0) activeDays++;
      for (var h = 0; h < 24; h++) {
        hourly[h] += day.hours[h];
      }
      weekday[date.weekday - 1] += day.ms;
      if (day.ms > busiestMs) {
        busiestMs = day.ms;
        busiestDay = date;
      }
      day.tracks.forEach((id, value) {
        final sum = perTrack.putIfAbsent(id, () => [0, 0]);
        sum[0] += value[0];
        sum[1] += value[1];
      });
    }

    if (period == StatsPeriod.allTime) {
      _legacy.forEach((id, value) {
        final sum = perTrack.putIfAbsent(id, () => [0, 0]);
        sum[0] += value[0];
        sum[1] += value[1];
        plays += value[0];
        totalMs += value[1];
      });
    }

    final topTracks = <TrackStat>[
      for (final entry in perTrack.entries)
        if (_tracks[entry.key] case final track?)
          TrackStat(track, entry.value[0], entry.value[1]),
    ]..sort(_byPlaysThenTime);

    final artists = <String, _Tally>{};
    final albums = <String, _Tally>{};
    for (final stat in topTracks) {
      final track = stat.track;
      final names = splitArtists(track.artist);
      for (var i = 0; i < names.length; i++) {
        final tally = artists.putIfAbsent(names[i].toLowerCase(), _Tally.new);
        tally.add(stat, name: names[i], id: i == 0 ? track.artistId : null);
      }
      final album = track.album?.trim();
      if (album != null && album.isNotEmpty) {
        albums
            .putIfAbsent('${album.toLowerCase()}|${names.first.toLowerCase()}',
                _Tally.new)
            .add(stat, name: album, id: track.albumId, artist: names.first);
      }
    }

    int? previousTotal;
    if (period != StatsPeriod.allTime) {
      final previousEnd = _dayKey(start.subtract(const Duration(days: 1)));
      final previousStart = _dayKey(start.subtract(Duration(days: days)));
      previousTotal = 0;
      for (final entry in _days.entries) {
        if (entry.key >= previousStart && entry.key <= previousEnd) {
          previousTotal = previousTotal! + entry.value.ms;
        }
      }
    }

    var newTracks = 0;
    _firstHeard.forEach((id, first) {
      if (first >= startKey && first <= todayKey) newTracks++;
    });

    final (current, longest) = _streaks(todayKey);

    return ListeningSummary(
      period: period,
      totalMs: totalMs,
      plays: plays,
      uniqueTracks: perTrack.length,
      uniqueArtists: artists.length,
      previousTotalMs: previousTotal,
      buckets: _buckets(period, start, today, days),
      hourly: hourly,
      weekday: weekday,
      topTracks: topTracks.take(limit).toList(),
      topArtists: (artists.values.toList()..sort(_tallyOrder))
          .take(limit)
          .map(
            (t) => ArtistStat(
              name: t.name,
              artistId: t.id,
              plays: t.plays,
              ms: t.ms,
              imageUrl: t.imageUrl,
            ),
          )
          .toList(),
      topAlbums: (albums.values.toList()..sort(_tallyOrder))
          .take(limit)
          .map(
            (t) => AlbumStat(
              name: t.name,
              albumId: t.id,
              artist: t.artist ?? '',
              plays: t.plays,
              ms: t.ms,
              imageUrl: t.imageUrl,
            ),
          )
          .toList(),
      newTracks: newTracks,
      activeDays: activeDays,
      days: days,
      currentStreak: current,
      longestStreak: longest,
      busiestDay: busiestDay,
      busiestDayMs: busiestMs,
      firstDay: firstDay,
    );
  }

  static int _byPlaysThenTime(TrackStat a, TrackStat b) {
    final byPlays = b.plays.compareTo(a.plays);
    return byPlays != 0 ? byPlays : b.ms.compareTo(a.ms);
  }

  static int _tallyOrder(_Tally a, _Tally b) {
    final byTime = b.ms.compareTo(a.ms);
    return byTime != 0 ? byTime : b.plays.compareTo(a.plays);
  }

  /// Bars for the activity chart: one a day for a week or a month, one a
  /// month for a year or all time.
  List<StatsBucket> _buckets(
    StatsPeriod period,
    DateTime start,
    DateTime today,
    int days,
  ) {
    if (period == StatsPeriod.week || period == StatsPeriod.month) {
      return [
        for (var i = 0; i < days; i++)
          () {
            final date = start.add(Duration(days: i));
            return StatsBucket(
              start: date,
              ms: _days[_dayKey(date)]?.ms ?? 0,
              isCurrent: i == days - 1,
              isMonth: false,
            );
          }(),
      ];
    }
    final months = <StatsBucket>[];
    var month = DateTime(start.year, start.month);
    final last = DateTime(today.year, today.month);
    // All time can span years; the chart shows the last two at most.
    if (period == StatsPeriod.allTime) {
      final earliest = DateTime(last.year - 2, last.month + 1);
      if (month.isBefore(earliest)) month = earliest;
    }
    while (!month.isAfter(last)) {
      var ms = 0;
      final from = _dayKey(month);
      final to = _dayKey(DateTime(month.year, month.month + 1, 0));
      _days.forEach((key, day) {
        if (key >= from && key <= to) ms += day.ms;
      });
      months.add(
        StatsBucket(
          start: month,
          ms: ms,
          isCurrent: month == last,
          isMonth: true,
        ),
      );
      month = DateTime(month.year, month.month + 1);
    }
    return months;
  }

  /// The run of days with listening up to today (or up to yesterday, while
  /// today has none yet), and the longest run ever.
  (int, int) _streaks(int todayKey) {
    final active =
        _days.entries.where((e) => e.value.ms >= 60000).map((e) => e.key)
            .toList()
          ..sort();
    if (active.isEmpty) return (0, 0);
    var longest = 1;
    var run = 1;
    for (var i = 1; i < active.length; i++) {
      final gap = _dateOf(active[i]).difference(_dateOf(active[i - 1])).inDays;
      run = gap == 1 ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    final today = _dateOf(todayKey);
    final lastActive = _dateOf(active.last);
    final sinceLast = today.difference(lastActive).inDays;
    if (sinceLast > 1) return (0, longest);
    var current = 1;
    for (var i = active.length - 1; i > 0; i--) {
      final gap = _dateOf(active[i]).difference(_dateOf(active[i - 1])).inDays;
      if (gap != 1) break;
      current++;
    }
    return (current, longest);
  }

  /// "A, B & C feat. D" -> [A, B, C, D]. Each artist on a song gets its
  /// time, the way streaming services count collaborations.
  static List<String> splitArtists(String artist) {
    final parts = artist
        .split(
          RegExp(
            r'\s*(?:,|;|\s&\s|\sx\s|\s(?:feat\.?|ft\.?|featuring|with)\s)\s*',
            caseSensitive: false,
          ),
        )
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? [artist.trim().isEmpty ? 'Unknown artist' : artist] : parts;
  }
}

class _Tally {
  String name = '';
  String? id;
  String? artist;
  int plays = 0;
  int ms = 0;
  String? imageUrl;
  int _imageMs = -1;

  void add(TrackStat stat, {required String name, String? id, String? artist}) {
    if (this.name.isEmpty) this.name = name;
    if ((this.id == null || this.id!.isEmpty) && id != null && id.isNotEmpty) {
      this.id = id;
    }
    this.artist ??= artist;
    plays += stat.plays;
    ms += stat.ms;
    final thumb =
        stat.track.highResThumbnailUrl ?? stat.track.thumbnailUrl;
    if (thumb != null && stat.ms > _imageMs) {
      imageUrl = thumb;
      _imageMs = stat.ms;
    }
  }
}
