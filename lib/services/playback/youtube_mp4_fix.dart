import 'dart:io';
import 'dart:typed_data';

/// A fix for how AVFoundation (iOS) reads YouTube's AAC files. ExoPlayer and
/// libmpv read them correctly; nothing else needs this.
///
/// YouTube's audio renditions (itag 139/140) are fragmented MP4: an init
/// segment (`ftyp`, `moov`), a `sidx`, then `moof`/`mdat` fragments. The
/// `moov` declares the *whole* track's duration in `mvhd`, `tkhd` and
/// `mdhd`, although every sample lives in the fragments. AVFoundation treats
/// that declaration as un-fragmented media and adds the fragments on top, so
/// each track reports about twice its length (BitChord-iOS measured
/// dQw4w9WgXcQ itag 140 at 426.13 s against 213.04 s of audio). The seek bar
/// runs to double, and anything timed off the duration (crossfades, the end
/// of the track) goes wrong.
///
/// Zeroing those declared durations makes AVFoundation take the length from
/// the fragments alone. Only header fields change, never sample data, and
/// only in a `moov` that carries an `mvex` (the mark of a fragmented file):
/// an ordinary MP4 declares its real duration there.
///
/// Port of BitChord-iOS's YouTubeMP4InitSegment (GPL-3.0).
abstract final class YouTubeMp4Fix {
  /// How much of a file's opening to read looking for the `moov`. YouTube's
  /// is well under a kilobyte; this leaves plenty of room.
  static const headWindow = 256 * 1024;

  /// Zeroes the declared durations in every fragmented `moov` inside [data],
  /// which must start at file offset 0. Returns how many fields changed.
  static int patchDurations(Uint8List data) {
    var patched = 0;
    for (final box in _boxes(data, 0, data.length)) {
      if (box.type != 'moov') continue;
      if (!_boxes(data, box.bodyStart, box.end).any((b) => b.type == 'mvex')) continue;
      patched += _patchContainer(data, box);
    }
    return patched;
  }

  /// Whether [data] (from offset 0) starts like an MP4 (`ftyp` first).
  static bool isMp4(Uint8List data) =>
      data.length >= 8 &&
      data[4] == 0x66 && // f
      data[5] == 0x74 && // t
      data[6] == 0x79 && // y
      data[7] == 0x70; // p

  /// Where the top-level `moov` ends in [data] (from offset 0): the offset
  /// once it's wholly inside, -1 when more bytes are needed to tell, and -2
  /// when this isn't a file the fix applies to (not an MP4, or media data
  /// comes before any `moov`).
  static int moovEnd(Uint8List data) {
    if (data.length < 8) return -1;
    if (!isMp4(data)) return -2;
    var offset = 0;
    while (offset + 8 <= data.length) {
      final size = _u32(data, offset);
      final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
      if (size < 8) return -2; // size 0/1 (to end / 64-bit) never precedes YouTube's moov
      if (type == 'moov') {
        return offset + size <= data.length ? offset + size : -1;
      }
      if (type == 'mdat' || type == 'moof' || type == 'sidx') return -2;
      offset += size;
    }
    return -1;
  }

  /// Patches the file at [path] in place. Returns true when it changed.
  static Future<bool> patchFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final raf = await file.open(mode: FileMode.append);
    try {
      final length = await raf.length();
      if (length < 8) return false;
      await raf.setPosition(0);
      final head = await raf.read(length < headWindow ? length : headWindow);
      if (moovEnd(head) < 0) return false;
      if (patchDurations(head) == 0) return false;
      await raf.setPosition(0);
      await raf.writeFrom(head);
      return true;
    } catch (_) {
      return false;
    } finally {
      await raf.close();
    }
  }

  static int _patchContainer(Uint8List data, _Box container) {
    var patched = 0;
    for (final box in _boxes(data, container.bodyStart, container.end)) {
      switch (box.type) {
        case 'trak' || 'mdia':
          patched += _patchContainer(data, box);
        case 'mvhd' || 'mdhd':
          // version, flags, then created/modified, timescale, duration.
          patched += _zeroDuration(data, box, 16, 24);
        case 'tkhd':
          // version, flags, created/modified, track id, reserved, duration.
          patched += _zeroDuration(data, box, 20, 28);
      }
    }
    return patched;
  }

  static int _zeroDuration(Uint8List data, _Box box, int v0Offset, int v1Offset) {
    if (box.bodyStart >= box.end) return 0;
    final version = data[box.bodyStart];
    final offset = box.bodyStart + (version == 1 ? v1Offset : v0Offset);
    final width = version == 1 ? 8 : 4;
    if (offset + width > box.end) return 0;
    var changed = false;
    for (var i = offset; i < offset + width; i++) {
      if (data[i] != 0) {
        data[i] = 0;
        changed = true;
      }
    }
    return changed ? 1 : 0;
  }

  /// Boxes wholly inside `[start, end)`; stops at the first that runs past it.
  static List<_Box> _boxes(Uint8List data, int start, int end) {
    final result = <_Box>[];
    var offset = start;
    while (offset + 8 <= end) {
      var size = _u32(data, offset);
      var header = 8;
      if (size == 1) {
        if (offset + 16 > end) break;
        final large = _u64(data, offset + 8);
        if (large < 0) break;
        size = large;
        header = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < header || size > end - offset) break;
      final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
      result.add(_Box(type, offset + header, offset + size));
      offset += size;
    }
    return result;
  }

  static int _u32(Uint8List d, int o) =>
      (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  static int _u64(Uint8List d, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | d[o + i];
    }
    return v;
  }
}

class _Box {
  const _Box(this.type, this.bodyStart, this.end);
  final String type;
  final int bodyStart;
  final int end;
}
