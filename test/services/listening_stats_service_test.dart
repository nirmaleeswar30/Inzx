import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/services/listening_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final stats = ListeningStatsService.instance;

  Track song(
    String id, {
    String artist = 'Artist',
    String? album,
    String artistId = '',
  }) => Track(
    id: id,
    title: 'Song $id',
    artist: artist,
    artistId: artistId,
    album: album,
    duration: const Duration(minutes: 3),
  );

  DateTime daysAgo(int days, {int hour = 12}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour)
        .subtract(Duration(days: days));
  }

  const minute = 60000;

  setUp(stats.debugReset);

  test('a week sums only the last seven days', () {
    stats.debugRecord(song('a'), at: daysAgo(0), ms: 10 * minute);
    stats.debugRecord(song('a'), at: daysAgo(6), ms: 5 * minute);
    stats.debugRecord(song('b'), at: daysAgo(7), ms: 30 * minute);

    final week = stats.summarize(StatsPeriod.week);
    expect(week.totalMs, 15 * minute);
    expect(week.plays, 2);
    expect(week.uniqueTracks, 1);
    expect(week.buckets, hasLength(7));
    expect(week.buckets.last.isCurrent, isTrue);
    expect(week.buckets.last.ms, 10 * minute);
  });

  test('compares with the period before', () {
    stats.debugRecord(song('a'), at: daysAgo(1), ms: 30 * minute);
    stats.debugRecord(song('a'), at: daysAgo(9), ms: 20 * minute);
    final week = stats.summarize(StatsPeriod.week);
    expect(week.previousTotalMs, 20 * minute);
    expect(week.change, closeTo(0.5, 0.001));
  });

  test('time listened without a counted play still adds up', () {
    stats.debugRecord(
      song('skip'),
      at: daysAgo(0),
      ms: 10000,
      countPlay: false,
    );
    final week = stats.summarize(StatsPeriod.week);
    expect(week.totalMs, 10000);
    expect(week.plays, 0);
  });

  test('top songs rank by plays, then time', () {
    for (var i = 0; i < 3; i++) {
      stats.debugRecord(song('most'), at: daysAgo(i), ms: minute);
    }
    stats.debugRecord(song('long'), at: daysAgo(0), ms: 40 * minute);
    stats.debugRecord(song('short'), at: daysAgo(0), ms: 2 * minute);
    final ids = stats
        .summarize(StatsPeriod.week)
        .topTracks
        .map((t) => t.track.id)
        .toList();
    expect(ids, ['most', 'long', 'short']);
  });

  test('collaborations credit every artist', () {
    stats.debugRecord(
      song('duet', artist: 'Arijit Singh, Shreya Ghoshal'),
      at: daysAgo(0),
      ms: 10 * minute,
    );
    stats.debugRecord(
      song('solo', artist: 'Arijit Singh'),
      at: daysAgo(0),
      ms: 5 * minute,
    );
    final artists = stats.summarize(StatsPeriod.week).topArtists;
    expect(artists.first.name, 'Arijit Singh');
    expect(artists.first.ms, 15 * minute);
    expect(artists.map((a) => a.name), contains('Shreya Ghoshal'));
  });

  test('splits the usual ways artists are joined', () {
    expect(
      ListeningStatsService.splitArtists('A & B feat. C, D x E ft. F'),
      ['A', 'B', 'C', 'D', 'E', 'F'],
    );
    expect(ListeningStatsService.splitArtists('Simon & Garfunkel'), [
      'Simon',
      'Garfunkel',
    ]);
    expect(ListeningStatsService.splitArtists('Coldplay'), ['Coldplay']);
  });

  test('albums group by name and artist', () {
    stats.debugRecord(
      song('1', album: 'Parachutes', artist: 'Coldplay'),
      at: daysAgo(0),
      ms: 4 * minute,
    );
    stats.debugRecord(
      song('2', album: 'Parachutes', artist: 'Coldplay'),
      at: daysAgo(0),
      ms: 3 * minute,
    );
    final albums = stats.summarize(StatsPeriod.week).topAlbums;
    expect(albums, hasLength(1));
    expect(albums.single.ms, 7 * minute);
    expect(albums.single.plays, 2);
  });

  test('streaks count consecutive days with a minute or more', () {
    for (final d in [0, 1, 2]) {
      stats.debugRecord(song('a'), at: daysAgo(d), ms: 2 * minute);
    }
    // A gap, then a longer run further back.
    for (final d in [5, 6, 7, 8, 9]) {
      stats.debugRecord(song('a'), at: daysAgo(d), ms: 2 * minute);
    }
    // Under a minute doesn't keep a streak going.
    stats.debugRecord(song('a'), at: daysAgo(4), ms: 30000);
    final summary = stats.summarize(StatsPeriod.month);
    expect(summary.currentStreak, 3);
    expect(summary.longestStreak, 5);
  });

  test('a streak survives until today has listening', () {
    stats.debugRecord(song('a'), at: daysAgo(1), ms: 2 * minute);
    stats.debugRecord(song('a'), at: daysAgo(2), ms: 2 * minute);
    expect(stats.summarize(StatsPeriod.week).currentStreak, 2);
  });

  test('hours, weekdays and the busiest day', () {
    stats.debugRecord(song('a'), at: daysAgo(0, hour: 23), ms: 50 * minute);
    stats.debugRecord(song('a'), at: daysAgo(1, hour: 8), ms: 10 * minute);
    final week = stats.summarize(StatsPeriod.week);
    expect(week.peakHour, 23);
    expect(week.hourly[8], 10 * minute);
    expect(week.busiestDayMs, 50 * minute);
    expect(week.peakWeekday, daysAgo(0).weekday - 1);
  });

  test('new discoveries are songs first heard in the period', () {
    stats.debugRecord(song('old'), at: daysAgo(40), ms: minute);
    stats.debugRecord(song('old'), at: daysAgo(0), ms: minute);
    stats.debugRecord(song('new'), at: daysAgo(0), ms: minute);
    expect(stats.summarize(StatsPeriod.week).newTracks, 1);
  });

  test('old counts show in all time only', () {
    stats.debugLegacy(song('legacy'), plays: 12, ms: 0);
    stats.debugRecord(song('a'), at: daysAgo(0), ms: minute);
    expect(stats.summarize(StatsPeriod.week).plays, 1);
    final all = stats.summarize(StatsPeriod.allTime);
    expect(all.plays, 13);
    expect(all.topTracks.first.track.id, 'legacy');
  });

  test('a year is twelve months, this month last', () {
    stats.debugRecord(song('a'), at: daysAgo(0), ms: minute);
    final year = stats.summarize(StatsPeriod.year);
    expect(year.buckets, hasLength(12));
    expect(year.buckets.every((b) => b.isMonth), isTrue);
    expect(year.buckets.last.isCurrent, isTrue);
    expect(year.buckets.last.ms, minute);
  });

  test('nothing recorded is empty', () {
    final week = stats.summarize(StatsPeriod.week);
    expect(week.isEmpty, isTrue);
    expect(week.currentStreak, 0);
    expect(stats.mostPlayed(), isEmpty);
  });
}
