import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// What [WebmTagger.readEmbedded] found in a file.
class WebmEmbedded {
  const WebmEmbedded({this.cover, this.lyrics});
  final Uint8List? cover;
  final String? lyrics;
}

/// Appends Matroska Tags (TITLE, ARTIST, ALBUM, LYRICS) and Attachments (cover.jpg)
/// to an Opus / WebM file in place.
class WebmTagger {
  static final Uint8List _ebmlHeaderId = Uint8List.fromList([
    0x1A,
    0x45,
    0xDF,
    0xA3,
  ]);
  static final Uint8List _segmentId = Uint8List.fromList([
    0x18,
    0x53,
    0x80,
    0x67,
  ]);
  static final Uint8List _idTags = Uint8List.fromList([0x12, 0x54, 0xC3, 0x67]);
  static final Uint8List _idTag = Uint8List.fromList([0x73, 0x73]);
  static final Uint8List _idTargets = Uint8List.fromList([0x63, 0xC0]);
  static final Uint8List _idSimpleTag = Uint8List.fromList([0x67, 0xC8]);
  static final Uint8List _idTagName = Uint8List.fromList([0x45, 0xA3]);
  static final Uint8List _idTagString = Uint8List.fromList([0x44, 0x87]);
  static final Uint8List _idAttachments = Uint8List.fromList([
    0x19,
    0x41,
    0xA4,
    0x69,
  ]);
  static final Uint8List _idAttachedFile = Uint8List.fromList([0x61, 0xA7]);
  static final Uint8List _idFileName = Uint8List.fromList([0x46, 0x6E]);
  static final Uint8List _idFileMimeType = Uint8List.fromList([0x46, 0x60]);
  static final Uint8List _idFileData = Uint8List.fromList([0x46, 0x5C]);
  static final Uint8List _idFileUid = Uint8List.fromList([0x46, 0xAE]);
  static final Uint8List _idCluster = Uint8List.fromList([
    0x1F,
    0x43,
    0xB6,
    0x75,
  ]);

  /// The cover and lyrics embedded in WebM/Opus [bytes], if any.
  ///
  /// Follows the file's element tree, so attachments are only looked for
  /// where they can be. Scanning the whole file for a FileData ID won't do:
  /// those two bytes turn up at random dozens of times in the audio.
  static WebmEmbedded readEmbedded(Uint8List bytes) {
    if (bytes.length < 16 || !_regionMatches(bytes, 0, _ebmlHeaderId)) {
      return const WebmEmbedded();
    }
    final headerSize = _readSize(bytes, _ebmlHeaderId.length);
    if (headerSize == null) return const WebmEmbedded();
    final segmentOffset =
        _ebmlHeaderId.length + headerSize.width + headerSize.value;
    if (!_regionMatches(bytes, segmentOffset, _segmentId)) {
      return const WebmEmbedded();
    }
    final segmentSize = _readSize(bytes, segmentOffset + _segmentId.length);
    if (segmentSize == null) return const WebmEmbedded();

    final start = segmentOffset + _segmentId.length + segmentSize.width;
    final end = segmentSize.isUnknown
        ? bytes.length
        : min(start + segmentSize.value, bytes.length);

    Uint8List? cover;
    String? lyrics;

    void read(int position, _EbmlElement element) {
      if (_regionMatches(bytes, position, _idTags)) {
        lyrics ??= _lyricsIn(bytes, element.contentStart, element.contentEnd);
      } else if (_regionMatches(bytes, position, _idAttachments)) {
        cover ??= _coverIn(bytes, element.contentStart, element.contentEnd);
      }
    }

    var position = start;
    while (position < end) {
      final element = _readElement(bytes, position, end);
      if (element == null) break;
      if (element.isUnknownSize) {
        // A live-style cluster runs on with no stated length, so it can't be
        // stepped over. Tags and attachments are appended after all the
        // audio, so go straight to the last of each.
        if (_regionMatches(bytes, position, _idCluster)) {
          for (final id in [_idTags, _idAttachments]) {
            final at = _lastIndexOf(bytes, id, position + id.length);
            if (at < 0) continue;
            final found = _readElement(bytes, at, end);
            if (found != null && !found.isUnknownSize) read(at, found);
          }
        }
        break;
      }
      read(position, element);
      position = element.contentEnd;
    }
    return WebmEmbedded(cover: cover, lyrics: lyrics);
  }

  static Uint8List? _coverIn(Uint8List bytes, int start, int end) {
    var position = start;
    while (position < end) {
      final file = _readElement(bytes, position, end);
      if (file == null || file.isUnknownSize) return null;
      if (_regionMatches(bytes, position, _idAttachedFile)) {
        var inner = file.contentStart;
        while (inner < file.contentEnd) {
          final field = _readElement(bytes, inner, file.contentEnd);
          if (field == null || field.isUnknownSize) break;
          if (_regionMatches(bytes, inner, _idFileData) &&
              field.contentEnd > field.contentStart) {
            return bytes.sublist(field.contentStart, field.contentEnd);
          }
          inner = field.contentEnd;
        }
      }
      position = file.contentEnd;
    }
    return null;
  }

  static String? _lyricsIn(Uint8List bytes, int start, int end) {
    var tag = start;
    while (tag < end) {
      final tagElement = _readElement(bytes, tag, end);
      if (tagElement == null || tagElement.isUnknownSize) return null;
      var simple = tagElement.contentStart;
      while (simple < tagElement.contentEnd) {
        final simpleElement = _readElement(
          bytes,
          simple,
          tagElement.contentEnd,
        );
        if (simpleElement == null || simpleElement.isUnknownSize) break;
        if (_regionMatches(bytes, simple, _idSimpleTag)) {
          final value = _lyricsValue(bytes, simpleElement);
          if (value != null) return value;
        }
        simple = simpleElement.contentEnd;
      }
      tag = tagElement.contentEnd;
    }
    return null;
  }

  /// The value of a SimpleTag, if its name is LYRICS.
  static String? _lyricsValue(Uint8List bytes, _EbmlElement simpleTag) {
    String? name;
    String? value;
    var position = simpleTag.contentStart;
    while (position < simpleTag.contentEnd) {
      final field = _readElement(bytes, position, simpleTag.contentEnd);
      if (field == null || field.isUnknownSize) break;
      String text() => utf8.decode(
        bytes.sublist(field.contentStart, field.contentEnd),
        allowMalformed: true,
      );
      if (_regionMatches(bytes, position, _idTagName)) {
        name = text();
      } else if (_regionMatches(bytes, position, _idTagString)) {
        value = text();
      }
      position = field.contentEnd;
    }
    if (name?.toUpperCase() != 'LYRICS') return null;
    return value == null || value.trim().isEmpty ? null : value;
  }

  /// The element at [offset]: an ID (whose length its first byte states)
  /// and a size. Null if it doesn't fit before [limit].
  static _EbmlElement? _readElement(Uint8List bytes, int offset, int limit) {
    if (offset >= limit) return null;
    final first = bytes[offset] & 0xFF;
    var idWidth = 1;
    var mask = 0x80;
    while (mask != 0 && (first & mask) == 0) {
      mask >>= 1;
      idWidth++;
    }
    if (mask == 0 || idWidth > 4) return null;
    final size = _readSize(bytes, offset + idWidth);
    if (size == null) return null;
    final contentStart = offset + idWidth + size.width;
    if (contentStart > limit) return null;
    if (size.isUnknown) {
      return _EbmlElement(contentStart, limit, isUnknownSize: true);
    }
    final contentEnd = contentStart + size.value;
    if (contentEnd > limit) return null;
    return _EbmlElement(contentStart, contentEnd);
  }

  static int _lastIndexOf(Uint8List bytes, Uint8List pattern, int floor) {
    for (var i = bytes.length - pattern.length; i >= floor; i--) {
      if (_regionMatches(bytes, i, pattern)) return i;
    }
    return -1;
  }

  /// Tag WebM/Opus bytes with metadata.
  /// Returns the tagged bytes, or original bytes if tagging fails.
  static Uint8List tag(
    Uint8List bytes, {
    String? title,
    String? artist,
    String? album,
    String? lyrics,
    Uint8List? coverBytes,
    bool coverIsPng = false,
  }) {
    try {
      final tail = _buildTail(
        title: title,
        artist: artist,
        album: album,
        lyrics: lyrics,
        coverBytes: coverBytes,
        coverIsPng: coverIsPng,
      );
      if (tail.isEmpty) return bytes;
      return _insert(bytes, tail);
    } catch (_) {
      return bytes;
    }
  }

  static Uint8List _insert(Uint8List bytes, Uint8List tail) {
    if (bytes.length < 16 || !_regionMatches(bytes, 0, _ebmlHeaderId)) {
      return bytes;
    }

    final headerSize = _readSize(bytes, _ebmlHeaderId.length);
    if (headerSize == null) return bytes;

    final segmentIdOffset =
        _ebmlHeaderId.length + headerSize.width + headerSize.value;
    if (segmentIdOffset + 4 > bytes.length ||
        !_regionMatches(bytes, segmentIdOffset, _segmentId)) {
      return bytes;
    }

    final segmentSize = _readSize(bytes, segmentIdOffset + _segmentId.length);
    if (segmentSize == null) return bytes;

    final segmentContentStart =
        segmentIdOffset + _segmentId.length + segmentSize.width;

    if (segmentSize.isUnknown) {
      final out = Uint8List(bytes.length + tail.length);
      out.setRange(0, bytes.length, bytes);
      out.setRange(bytes.length, out.length, tail);
      return out;
    }

    final declaredEnd = segmentContentStart + segmentSize.value;
    if (declaredEnd != bytes.length) return bytes;

    final newSize = segmentSize.value + tail.length;
    final maxForWidth = (1 << (7 * segmentSize.width)) - 2;
    if (newSize > maxForWidth) return bytes;

    final out = Uint8List(bytes.length + tail.length);
    out.setRange(0, bytes.length, bytes);
    out.setRange(bytes.length, out.length, tail);
    _writeVint(
      out,
      segmentIdOffset + _segmentId.length,
      newSize,
      segmentSize.width,
    );
    return out;
  }

  static Uint8List _buildTail({
    String? title,
    String? artist,
    String? album,
    String? lyrics,
    Uint8List? coverBytes,
    bool coverIsPng = false,
  }) {
    final elements = <Uint8List>[];

    final simpleTags = <Uint8List>[];
    if (title != null && title.trim().isNotEmpty) {
      simpleTags.add(_simpleTag('TITLE', title.trim()));
    }
    if (artist != null && artist.trim().isNotEmpty) {
      simpleTags.add(_simpleTag('ARTIST', artist.trim()));
    }
    if (album != null && album.trim().isNotEmpty) {
      simpleTags.add(_simpleTag('ALBUM', album.trim()));
    }
    if (lyrics != null && lyrics.trim().isNotEmpty) {
      simpleTags.add(_simpleTag('LYRICS', lyrics.trim()));
    }

    if (simpleTags.isNotEmpty) {
      final targets = _elem(_idTargets, Uint8List(0));
      final tagPayload = _concat([targets, ...simpleTags]);
      elements.add(_elem(_idTags, _elem(_idTag, tagPayload)));
    }

    if (coverBytes != null && coverBytes.isNotEmpty) {
      final fileName = _elem(_idFileName, utf8.encode('cover.jpg'));
      final mime = coverIsPng ? 'image/png' : 'image/jpeg';
      final fileMime = _elem(_idFileMimeType, ascii.encode(mime));
      final fileUid = _elem(
        _idFileUid,
        Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1]),
      );
      final fileData = _elem(_idFileData, coverBytes);
      final attachedFile = _elem(
        _idAttachedFile,
        _concat([fileName, fileMime, fileUid, fileData]),
      );
      elements.add(_elem(_idAttachments, attachedFile));
    }

    return _concat(elements);
  }

  static Uint8List _simpleTag(String name, String value) {
    final nameElem = _elem(_idTagName, ascii.encode(name));
    final stringElem = _elem(_idTagString, utf8.encode(value));
    return _elem(_idSimpleTag, _concat([nameElem, stringElem]));
  }

  static Uint8List _elem(Uint8List id, List<int> payload) {
    final vint = _encodeVint(payload.length);
    final out = Uint8List(id.length + vint.length + payload.length);
    out.setRange(0, id.length, id);
    out.setRange(id.length, id.length + vint.length, vint);
    out.setRange(id.length + vint.length, out.length, payload);
    return out;
  }

  static _EbmlSize? _readSize(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return null;
    final first = bytes[offset] & 0xFF;
    var width = 1;
    var mask = 0x80;
    while (mask != 0 && (first & mask) == 0) {
      mask >>= 1;
      width++;
    }
    if (mask == 0 || offset + width > bytes.length) return null;
    var value = first & (mask - 1);
    for (var i = 1; i < width; i++) {
      value = (value << 8) | (bytes[offset + i] & 0xFF);
    }
    final maxVal = (1 << (7 * width)) - 1;
    return _EbmlSize(value, width, value == maxVal);
  }

  static Uint8List _encodeVint(int value) {
    var width = 1;
    while (width < 8 && value > (1 << (7 * width)) - 2) {
      width++;
    }
    final bytes = Uint8List(width);
    _writeVint(bytes, 0, value, width);
    return bytes;
  }

  static void _writeVint(Uint8List bytes, int offset, int value, int width) {
    var v = value;
    for (var i = width - 1; i >= 0; i--) {
      bytes[offset + i] = v & 0xFF;
      v >>= 8;
    }
    bytes[offset] = (bytes[offset] | (0x80 >> (width - 1))) & 0xFF;
  }

  static bool _regionMatches(Uint8List bytes, int offset, Uint8List other) {
    if (offset < 0 || offset + other.length > bytes.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (bytes[offset + i] != other[i]) return false;
    }
    return true;
  }

  static Uint8List _concat(List<List<int>> chunks) {
    final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final out = Uint8List(total);
    var p = 0;
    for (final c in chunks) {
      out.setRange(p, p + c.length, c);
      p += c.length;
    }
    return out;
  }
}

class _EbmlElement {
  final int contentStart;
  final int contentEnd;
  final bool isUnknownSize;
  const _EbmlElement(
    this.contentStart,
    this.contentEnd, {
    this.isUnknownSize = false,
  });
}

class _EbmlSize {
  final int value;
  final int width;
  final bool isUnknown;
  const _EbmlSize(this.value, this.width, this.isUnknown);
}
