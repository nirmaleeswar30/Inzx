import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/addons/addon_models.dart';
import 'package:inzx/services/addons/addon_service.dart';

AddonTrack _hit(String id, String title, String album, {int seconds = 240}) =>
    AddonTrack(
      id: id,
      title: title,
      artist: 'Devi Sri Prasad',
      album: album,
      duration: Duration(seconds: seconds),
      audioQuality: 'LOSSLESS',
      isAtmos: false,
    );

void main() {
  final dubs = [
    _hit('te', 'Fire Song', 'Kanguva (Telugu)'),
    _hit('ta', 'Fire Song', 'Kanguva (Tamil)'),
    _hit('hi', 'Fire Song', 'Kanguva (Hindi)'),
  ];

  AddonTrack? pick(List<AddonTrack> hits, {String title = 'Fire Song', String? album}) =>
      AddonService.pickBest(
        hits,
        title: title,
        artist: 'Devi Sri Prasad',
        album: album,
        duration: const Duration(seconds: 240),
      );

  test('a tagged track takes the copy in its own language', () {
    expect(pick(dubs, album: 'Kanguva (Tamil)')?.id, 'ta');
    expect(pick(dubs, title: 'Fire Song (Tamil)', album: 'Kanguva')?.id, 'ta');
  });

  test('a language named inside "(From ...)" counts', () {
    final hit = AddonService.pickBest(
      dubs,
      title: 'Fire Song',
      sourceTitle: 'Fire Song (From "Kanguva (Hindi)")',
      artist: 'Devi Sri Prasad',
      duration: const Duration(seconds: 240),
    );
    expect(hit?.id, 'hi');
  });

  test('an untagged track never takes a dub', () {
    expect(pick(dubs, album: 'Kanguva'), isNull);
    final withOriginal = [...dubs, _hit('orig', 'Fire Song', 'Kanguva')];
    expect(pick(withOriginal, album: 'Kanguva')?.id, 'orig');
  });

  test('take markers must agree both ways', () {
    final hits = [
      _hit('remix', 'Fire Song (Remix)', 'Kanguva'),
      _hit('plain', 'Fire Song', 'Kanguva'),
    ];
    expect(pick(hits)?.id, 'plain');
    expect(pick(hits, title: 'Fire Song (Remix)')?.id, 'remix');
    expect(AddonService.takeMarkers('Let Me Live'), isEmpty);
    expect(AddonService.takeMarkers('Song - Lo-Fi Version'), {'lofi'});
  });

  test('a take on the album completes the row (KALYANI on "KALYANI (Remix)")', () {
    final hits = [
      _hit('remix', 'KALYANI', 'KALYANI (Remix)'),
      _hit('original', 'KALYANI', 'KALYANI'),
    ];
    expect(pick(hits, title: 'KALYANI (Remix)')?.id, 'remix');
    // Only in that direction: the plain song doesn't take the remix album.
    expect(pick(hits, title: 'KALYANI')?.id, 'original');
    // And an album's other takes are release naming, not this row's take.
    expect(pick([_hit('x', 'KALYANI', 'KALYANI (Live)')], title: 'KALYANI')?.id, 'x');
  });

  test('a title normalisation empties matches nothing', () {
    expect(pick([_hit('x', 'பாடல்', 'Album')], title: 'பாடல்'), isNull);
  });
}
