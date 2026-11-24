import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/addons/dash_manifest.dart';
import 'package:inzx/services/playback/dash_fmp4_audio_source.dart';

Uint8List box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...ascii.encode(type),
    ...payload,
  ]);
}

/// A CDN that serves [files] and counts what it was asked.
class FakeFetcher implements DashFetcher {
  FakeFetcher(this.files);
  final Map<String, Uint8List> files;
  int ranges = 0;

  Uint8List _file(Uri uri) => files[uri.toString()] ?? (throw StateError('no $uri'));

  @override
  Future<Uint8List> whole(Uri uri) async => Uint8List.fromList(_file(uri));

  @override
  Future<({Uint8List head, int total})> head(Uri uri, int bytes) async {
    final f = _file(uri);
    return (head: Uint8List.sublistView(f, 0, min(bytes, f.length)), total: f.length);
  }

  @override
  Stream<List<int>> range(Uri uri, int from, int to) async* {
    ranges++;
    final f = _file(uri);
    // In small chunks, as a network would.
    for (var at = from; at < to; at += 7) {
      yield f.sublist(at, min(at + 7, to));
    }
  }
}

void main() {
  const mpd = '''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT12S">
 <Period><AdaptationSet contentType="audio" mimeType="audio/mp4">
  <Representation id="FLAC" codecs="flac" bandwidth="1000">
   <SegmentTemplate timescale="1" initialization="https://cdn.test/init.mp4" media="https://cdn.test/\$Number\$.mp4" startNumber="1">
    <SegmentTimeline><S d="4" r="2"/></SegmentTimeline>
   </SegmentTemplate>
  </Representation>
 </AdaptationSet></Period>
</MPD>''';
  final manifestUrl = 'data:application/dash+xml;base64,${base64Encode(utf8.encode(mpd))}';

  test('Atmos DASH selects Dolby over FLAC and fails on a stereo-only MPD', () {
    final mixed = mpd.replaceFirst(
      '</AdaptationSet>',
      '<Representation id="dolby" codecs="ec-3" bandwidth="640">'
      '<BaseURL>https://cdn.test/atmos.mp4</BaseURL><SegmentBase/>'
      '</Representation></AdaptationSet>',
    );
    expect(DashManifest.parse(mixed).codecs, 'flac');
    expect(DashManifest.parse(mixed, preferAtmos: true).codecs, 'ec-3');
    expect(() => DashManifest.parse(mpd, preferAtmos: true), throwsFormatException);
  });

  // init: ftyp + moov (no mvex: left as it is); media: styp + sidx + moof + mdat.
  final init = Uint8List.fromList([...box('ftyp', [1, 2, 3, 4]), ...box('moov', List.filled(20, 9))]);
  Uint8List segment(int n) => Uint8List.fromList([
        ...box('styp', [0, 0, 0, n]),
        ...box('sidx', List.filled(12, n)),
        ...box('moof', List.filled(16, 100 + n)),
        ...box('mdat', List.generate(40 + n, (i) => (i * n) & 0xff)),
      ]);
  final files = {
    'https://cdn.test/init.mp4': init,
    for (var n = 1; n <= 3; n++) 'https://cdn.test/$n.mp4': segment(n),
  };
  // What the stitched file must be: init, then each segment from its moof.
  final expected = Uint8List.fromList([
    ...init,
    for (var n = 1; n <= 3; n++) ...segment(n).sublist(DashFileLayout.moofOffset(segment(n))),
  ]);

  test('moofOffset skips the leading styp and sidx', () {
    expect(DashFileLayout.moofOffset(segment(1)), 12 + 20);
    expect(DashFileLayout.moofOffset(box('moof', [1])), 0);
    // A probe too short to reach the moof keeps the whole segment.
    expect(DashFileLayout.moofOffset(Uint8List.sublistView(segment(1), 0, 10)), 0);
  });

  test('lays the segments out as one fragmented MP4', () async {
    final layout = await DashFileLayout.build(manifestUrl, FakeFetcher(files));
    expect(layout.parts, hasLength(3));
    expect(layout.length, expected.length);
    expect(layout.parts.first.offset, init.length);
  });

  test('any byte range reads back exactly', () async {
    final fetcher = FakeFetcher(files);
    final layout = await DashFileLayout.build(manifestUrl, fetcher);
    final random = Random(7);
    for (var i = 0; i < 200; i++) {
      final a = random.nextInt(expected.length);
      final b = a + random.nextInt(expected.length - a + 1);
      final got = <int>[];
      await layout.read(a, b, fetcher).forEach(got.addAll);
      expect(got, expected.sublist(a, b), reason: 'bytes $a-$b');
    }
    final all = <int>[];
    await layout.read(0, expected.length, fetcher).forEach(all.addAll);
    expect(all, expected);
  });
}
