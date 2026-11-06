import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Turns FLAC audio in a fragmented MP4 (what DASH lossless streams deliver)
/// into a plain `.flac` file, without re-encoding.
///
/// Stitched-together DASH segments play, but they carry no index, so the
/// player can't seek in them. A FLAC frame is self-contained, so the frames
/// can simply be lifted out of each `mdat` behind the stream header kept in
/// the `dfLa` box. The bytes of the audio are unchanged.
class FlacRemuxer {
  /// Writes [output] from [input]. Returns false, with nothing written, when
  /// [input] isn't single-track fragmented FLAC (ALAC, say, or a regular
  /// non-fragmented MP4, which seeks fine as it is).
  static Future<bool> remux(File input, File output) async {
    final raf = await input.open();
    final mdats = <({int offset, int length})>[];
    Uint8List? moov;
    var durationTicks = 0;
    var moofCount = 0;
    try {
      final fileLength = await raf.length();
      var position = 0;
      while (position + 8 <= fileLength) {
        await raf.setPosition(position);
        final header = await raf.read(16);
        if (header.length < 8) break;
        final view = ByteData.sublistView(header);
        var size = view.getUint32(0);
        final type = latin1.decode(header.sublist(4, 8));
        var headerLength = 8;
        if (size == 1) {
          if (header.length < 16) break;
          size = view.getUint64(8);
          headerLength = 16;
        } else if (size == 0) {
          size = fileLength - position;
        }
        if (size < headerLength || position + size > fileLength) break;

        final contentOffset = position + headerLength;
        final contentLength = size - headerLength;
        if (type == 'moov') {
          await raf.setPosition(contentOffset);
          moov = await raf.read(contentLength);
        } else if (type == 'moof') {
          await raf.setPosition(contentOffset);
          final ticks = _moofDuration(
            await raf.read(contentLength),
            _trexDefaultDuration(moov),
          );
          if (ticks == null) return false;
          durationTicks += ticks;
          moofCount++;
        } else if (type == 'mdat') {
          mdats.add((offset: contentOffset, length: contentLength));
        }
        position += size;
      }

      if (moov == null || moofCount == 0 || mdats.isEmpty) return false;
      final stream = _flacStreamFrom(moov);
      if (stream == null) return false;
      final header = _withTotalSamples(
        stream.blocks,
        durationTicks,
        stream.timescale,
      );

      final sink = output.openWrite();
      try {
        sink.add(latin1.encode('fLaC'));
        sink.add(header);
        for (final mdat in mdats) {
          await sink.addStream(
            input.openRead(mdat.offset, mdat.offset + mdat.length),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return true;
    } catch (_) {
      if (await output.exists()) await output.delete();
      return false;
    } finally {
      await raf.close();
    }
  }

  /// The FLAC metadata blocks and media timescale, from a `moov` holding
  /// exactly one track of `fLaC` samples.
  static ({Uint8List blocks, int timescale})? _flacStreamFrom(Uint8List moov) {
    final traks = _children(moov, 0, moov.length, 'trak');
    if (traks.length != 1) return null;
    final mdia = _firstChild(moov, traks.single, 'mdia');
    if (mdia == null) return null;
    final mdhd = _firstChild(moov, mdia, 'mdhd');
    final stbl = _descend(moov, mdia, const ['minf', 'stbl']);
    if (mdhd == null || stbl == null) return null;
    final stsd = _firstChild(moov, stbl, 'stsd');
    if (stsd == null) return null;

    // stsd: version/flags + entry count, then the sample entries. An audio
    // sample entry has 28 bytes of fixed fields before its child boxes.
    final entry = _firstChild(moov, (start: stsd.start + 8, end: stsd.end), 'fLaC');
    if (entry == null) return null;
    final dfLa = _firstChild(moov, (start: entry.start + 28, end: entry.end), 'dfLa');
    if (dfLa == null) return null;

    // dfLa: version/flags, then FLAC metadata blocks exactly as in a file.
    final blocks = Uint8List.fromList(moov.sublist(dfLa.start + 4, dfLa.end));
    if (blocks.length < 38 || (blocks[0] & 0x7F) != 0) return null;

    final view = ByteData.sublistView(moov);
    final version = moov[mdhd.start];
    final timescale = view.getUint32(mdhd.start + (version == 1 ? 20 : 12));
    return (blocks: blocks, timescale: timescale);
  }

  /// [blocks] with STREAMINFO's total sample count filled in. Segmented
  /// streams leave it zero, and without it the player can't work out where
  /// to seek in a file with no seek table. Left as it was if the fragments
  /// didn't state their durations.
  static Uint8List _withTotalSamples(
    Uint8List blocks,
    int durationTicks,
    int timescale,
  ) {
    if (durationTicks <= 0 || timescale <= 0) return blocks;
    // STREAMINFO body starts at 4. Sample rate is the 20 bits from byte 10.
    final sampleRate =
        (blocks[14] << 12) | (blocks[15] << 4) | (blocks[16] >> 4);
    if (sampleRate <= 0) return blocks;
    final total = timescale == sampleRate
        ? durationTicks
        : durationTicks * sampleRate ~/ timescale;
    // Total samples is the 36 bits that end at STREAMINFO byte 17.
    blocks[17] = (blocks[17] & 0xF0) | ((total >> 32) & 0x0F);
    blocks[18] = (total >> 24) & 0xFF;
    blocks[19] = (total >> 16) & 0xFF;
    blocks[20] = (total >> 8) & 0xFF;
    blocks[21] = total & 0xFF;
    return blocks;
  }

  /// The ticks a `moof` covers, or null if it holds more than one track (its
  /// `mdat` would then interleave them).
  static int? _moofDuration(Uint8List moof, int trexDefault) {
    final trafs = _children(moof, 0, moof.length, 'traf');
    if (trafs.length > 1) return null;
    if (trafs.isEmpty) return 0;
    final traf = trafs.single;
    final view = ByteData.sublistView(moof);

    var defaultDuration = trexDefault;
    final tfhd = _firstChild(moof, traf, 'tfhd');
    if (tfhd != null) {
      final flags = view.getUint32(tfhd.start) & 0xFFFFFF;
      var p = tfhd.start + 8;
      if (flags & 0x01 != 0) p += 8; // base-data-offset
      if (flags & 0x02 != 0) p += 4; // sample-description-index
      if (flags & 0x08 != 0) defaultDuration = view.getUint32(p);
    }

    var ticks = 0;
    for (final trun in _children(moof, traf.start, traf.end, 'trun')) {
      final flags = view.getUint32(trun.start) & 0xFFFFFF;
      final count = view.getUint32(trun.start + 4);
      var p = trun.start + 8;
      if (flags & 0x01 != 0) p += 4; // data-offset
      if (flags & 0x04 != 0) p += 4; // first-sample-flags
      if (flags & 0x100 == 0) {
        ticks += count * defaultDuration;
        continue;
      }
      final stride =
          4 +
          (flags & 0x200 != 0 ? 4 : 0) +
          (flags & 0x400 != 0 ? 4 : 0) +
          (flags & 0x800 != 0 ? 4 : 0);
      for (var i = 0; i < count; i++) {
        ticks += view.getUint32(p);
        p += stride;
      }
    }
    return ticks;
  }

  static int _trexDefaultDuration(Uint8List? moov) {
    if (moov == null) return 0;
    final trex = _descend(
      moov,
      (start: 0, end: moov.length),
      const ['mvex', 'trex'],
    );
    if (trex == null || trex.start + 16 > trex.end) return 0;
    // version/flags, track id, description index, then the default duration.
    return ByteData.sublistView(moov).getUint32(trex.start + 12);
  }

  static ({int start, int end})? _descend(
    Uint8List bytes,
    ({int start, int end}) from,
    List<String> path,
  ) {
    ({int start, int end})? current = from;
    for (final type in path) {
      if (current == null) return null;
      current = _firstChild(bytes, current, type);
    }
    return current;
  }

  static ({int start, int end})? _firstChild(
    Uint8List bytes,
    ({int start, int end}) parent,
    String type,
  ) {
    final found = _children(bytes, parent.start, parent.end, type);
    return found.isEmpty ? null : found.first;
  }

  /// The content ranges of the [type] boxes directly inside [start]..[end].
  static List<({int start, int end})> _children(
    Uint8List bytes,
    int start,
    int end,
    String type,
  ) {
    final found = <({int start, int end})>[];
    final view = ByteData.sublistView(bytes);
    var p = start;
    while (p + 8 <= end) {
      var size = view.getUint32(p);
      var headerLength = 8;
      if (size == 1) {
        if (p + 16 > end) break;
        size = view.getUint64(p + 8);
        headerLength = 16;
      } else if (size == 0) {
        size = end - p;
      }
      if (size < headerLength || p + size > end) break;
      if (latin1.decode(bytes.sublist(p + 4, p + 8)) == type) {
        found.add((start: p + headerLength, end: p + size));
      }
      p += size;
    }
    return found;
  }
}
