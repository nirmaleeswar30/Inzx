import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/playback/youtube_mp4_fix.dart';

/// Builds a box: 32-bit size, 4-char type, body.
List<int> box(String type, List<int> body) {
  final size = 8 + body.length;
  return [
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...type.codeUnits,
    ...body,
  ];
}

List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

/// Version-0 mvhd/mdhd: version+flags, created, modified, timescale, duration.
List<int> headerV0(String type, int duration, {int extra = 0}) => box(type, [
  0, 0, 0, 0, // version 0, flags
  ...u32(1), ...u32(2), // created, modified
  if (type == 'tkhd') ...[...u32(1), ...u32(0)] else ...u32(44100), // track id + reserved, or timescale
  ...u32(duration),
  ...List.filled(extra, 7),
]);

/// A YouTube-shaped init segment: ftyp, a fragmented moov, then sidx/moof.
Uint8List youtubeHead({bool fragmented = true}) => Uint8List.fromList([
  ...box('ftyp', 'dash'.codeUnits + u32(0)),
  ...box('moov', [
    ...headerV0('mvhd', 9395000, extra: 80),
    if (fragmented) ...box('mvex', box('trex', List.filled(24, 0))),
    ...box('trak', [
      ...headerV0('tkhd', 9395000, extra: 60),
      ...box('mdia', headerV0('mdhd', 9395000, extra: 4)),
    ]),
  ]),
  ...box('sidx', List.filled(16, 1)),
  ...box('moof', List.filled(16, 2)),
]);

int durationAt(Uint8List d, String type) {
  final name = type.codeUnits;
  for (var i = 0; i + 4 <= d.length; i++) {
    if (d[i] == name[0] && d[i + 1] == name[1] && d[i + 2] == name[2] && d[i + 3] == name[3]) {
      final body = i + 4;
      final offset = body + (type == 'tkhd' ? 20 : 16);
      return (d[offset] << 24) | (d[offset + 1] << 16) | (d[offset + 2] << 8) | d[offset + 3];
    }
  }
  throw StateError('no $type');
}

void main() {
  test('zeroes mvhd, tkhd and mdhd durations in a fragmented moov', () {
    final head = youtubeHead();
    expect(durationAt(head, 'mvhd'), 9395000);
    expect(YouTubeMp4Fix.patchDurations(head), 3);
    expect(durationAt(head, 'mvhd'), 0);
    expect(durationAt(head, 'tkhd'), 0);
    expect(durationAt(head, 'mdhd'), 0);
    // Already patched: nothing left to change.
    expect(YouTubeMp4Fix.patchDurations(head), 0);
  });

  test('leaves an ordinary (unfragmented) MP4 alone', () {
    final head = youtubeHead(fragmented: false);
    expect(YouTubeMp4Fix.patchDurations(head), 0);
    expect(durationAt(head, 'mvhd'), 9395000);
  });

  test('moovEnd waits for the whole moov and rejects non-MP4 data', () {
    final head = youtubeHead();
    final end = YouTubeMp4Fix.moovEnd(head);
    expect(end, greaterThan(0));
    expect(String.fromCharCodes(head.sublist(end + 4, end + 8)), 'sidx');
    expect(YouTubeMp4Fix.moovEnd(Uint8List.sublistView(head, 0, end - 1)), -1);
    expect(YouTubeMp4Fix.moovEnd(Uint8List.fromList(box('mdat', [1, 2, 3]))), -2);
    expect(YouTubeMp4Fix.moovEnd(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0])), -2);
  });

  test('patchFile fixes a file in place without changing its length', () async {
    final dir = await Directory.systemTemp.createTemp('mp4fix');
    try {
      final file = File('${dir.path}/a.m4a');
      final head = youtubeHead();
      await file.writeAsBytes([...head, ...List.filled(5000, 9)]);
      expect(await YouTubeMp4Fix.patchFile(file.path), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.length, head.length + 5000);
      expect(durationAt(bytes, 'mdhd'), 0);
      expect(bytes.last, 9);
      expect(await YouTubeMp4Fix.patchFile(file.path), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
