import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a FLAC's STREAMINFO block says about its audio.
class FlacStreamInfo {
  const FlacStreamInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    this.duration,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Duration? duration;

  /// Reads a STREAMINFO block body. Null if [body] is too short or states no
  /// sample rate.
  static FlacStreamInfo? parse(Uint8List body) {
    if (body.length < 18) return null;
    // From byte 10: 20 bits of sample rate, 3 of channels - 1, 5 of bits per
    // sample - 1, then 36 of total samples.
    final sampleRate = (body[10] << 12) | (body[11] << 4) | (body[12] >> 4);
    if (sampleRate == 0) return null;
    final totalSamples =
        ((body[13] & 0x0F) << 32) |
        (body[14] << 24) |
        (body[15] << 16) |
        (body[16] << 8) |
        body[17];
    return FlacStreamInfo(
      sampleRate: sampleRate,
      channels: ((body[12] >> 1) & 0x07) + 1,
      bitsPerSample: (((body[12] & 0x01) << 4) | (body[13] >> 4)) + 1,
      duration: totalSamples == 0
          ? null
          : Duration(microseconds: totalSamples * 1000000 ~/ sampleRate),
    );
  }
}

/// Writes Vorbis comments (title, artist, album, lyrics) and a front-cover
/// PICTURE block into a FLAC file.
///
/// A FLAC can run to hundreds of megabytes, so unlike the other taggers this
/// works on the file: only the metadata blocks are read into memory, and the
/// audio frames are streamed across untouched. Seek tables stay valid because
/// their offsets count from the first frame, not from the start of the file.
class FlacTagger {
  static const int _typeStreamInfo = 0;
  static const int _typePadding = 1;
  static const int _typeVorbisComment = 4;
  static const int _typePicture = 6;

  /// The largest body a metadata block's 24-bit length can describe.
  static const int _maxBlockBody = 0xFFFFFF;

  /// The audio format [file]'s STREAMINFO states, or null if it isn't a
  /// readable FLAC. [FlacStreamInfo.duration] is null when the file doesn't
  /// say how long it is.
  static Future<FlacStreamInfo?> readStreamInfo(File file) async {
    final layout = await _readLayout(file);
    if (layout == null) return null;
    return FlacStreamInfo.parse(layout.blocks.first.body);
  }

  /// Tags [file] in place. Returns false, leaving the file as it was, when
  /// it isn't a readable FLAC.
  static Future<bool> tagFile(
    File file, {
    String? title,
    String? artist,
    String? album,
    String? lyrics,
    Uint8List? coverBytes,
    bool coverIsPng = false,
  }) async {
    final layout = await _readLayout(file);
    if (layout == null) return false;

    final fields = <String, String>{
      if (title != null && title.trim().isNotEmpty) 'TITLE': title.trim(),
      if (artist != null && artist.trim().isNotEmpty) 'ARTIST': artist.trim(),
      if (album != null && album.trim().isNotEmpty) 'ALBUM': album.trim(),
      if (lyrics != null && lyrics.trim().isNotEmpty) 'LYRICS': lyrics.trim(),
    };
    final hasCover = coverBytes != null && coverBytes.isNotEmpty;

    final blocks = <({int type, Uint8List body})>[];
    for (final block in layout.blocks) {
      if (block.type == _typePadding) continue;
      if (block.type == _typeVorbisComment) continue;
      if (block.type == _typePicture && hasCover) continue;
      blocks.add(block);
    }

    final existingComments = layout.blocks
        .where((b) => b.type == _typeVorbisComment)
        .map((b) => b.body)
        .firstOrNull;
    final comments = _mergeComments(existingComments, fields);
    if (comments != null) {
      blocks.insert(1, (type: _typeVorbisComment, body: comments));
    }
    if (hasCover) {
      final picture = _pictureBody(coverBytes, coverIsPng);
      if (picture.length <= _maxBlockBody) {
        blocks.add((type: _typePicture, body: picture));
      }
    }

    final tempFile = File('${file.path}.tagged');
    try {
      final sink = tempFile.openWrite();
      try {
        sink.add(latin1.encode('fLaC'));
        for (var i = 0; i < blocks.length; i++) {
          final block = blocks[i];
          final isLast = i == blocks.length - 1;
          sink.add([
            (isLast ? 0x80 : 0) | block.type,
            (block.body.length >> 16) & 0xFF,
            (block.body.length >> 8) & 0xFF,
            block.body.length & 0xFF,
          ]);
          sink.add(block.body);
        }
        await sink.addStream(file.openRead(layout.audioOffset));
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tempFile.rename(file.path);
      return true;
    } catch (_) {
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
  }

  /// The metadata blocks of [file] and where its audio frames begin. Any
  /// ID3v2 tag stuck on the front is skipped, and so dropped by the rewrite.
  static Future<
    ({List<({int type, Uint8List body})> blocks, int audioOffset})?
  >
  _readLayout(File file) async {
    final raf = await file.open();
    try {
      var offset = 0;
      final head = await raf.read(10);
      if (head.length < 4) return null;
      if (head.length == 10 &&
          head[0] == 0x49 && // I
          head[1] == 0x44 && // D
          head[2] == 0x33) {
        // 3
        final size =
            (head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9];
        offset = 10 + size;
      }
      await raf.setPosition(offset);
      final marker = await raf.read(4);
      if (marker.length < 4 || latin1.decode(marker) != 'fLaC') return null;
      offset += 4;

      final blocks = <({int type, Uint8List body})>[];
      while (true) {
        final header = await raf.read(4);
        if (header.length < 4) return null;
        final isLast = (header[0] & 0x80) != 0;
        final type = header[0] & 0x7F;
        final length = (header[1] << 16) | (header[2] << 8) | header[3];
        offset += 4;
        if (type == _typePadding) {
          // Padding is discarded, so there's no need to hold it in memory.
          await raf.setPosition(offset + length);
          blocks.add((type: type, body: Uint8List(0)));
        } else {
          final body = await raf.read(length);
          if (body.length < length) return null;
          blocks.add((type: type, body: body));
        }
        offset += length;
        if (isLast) break;
      }

      if (blocks.isEmpty || blocks.first.type != _typeStreamInfo) return null;
      return (blocks: blocks, audioOffset: offset);
    } finally {
      await raf.close();
    }
  }

  /// A Vorbis comment body holding [fields] plus whatever else [existing]
  /// already said (ISRC, track numbers…). Null when there is nothing to write.
  static Uint8List? _mergeComments(
    Uint8List? existing,
    Map<String, String> fields,
  ) {
    var vendor = 'Inzx';
    final kept = <String>[];
    if (existing != null) {
      final parsed = _parseComments(existing);
      if (parsed != null) {
        vendor = parsed.vendor;
        for (final comment in parsed.comments) {
          final separator = comment.indexOf('=');
          final key = separator > 0
              ? comment.substring(0, separator).toUpperCase()
              : '';
          if (!fields.containsKey(key)) kept.add(comment);
        }
      }
    }
    final comments = [
      ...kept,
      for (final entry in fields.entries) '${entry.key}=${entry.value}',
    ];
    if (comments.isEmpty) return null;

    final out = BytesBuilder();
    final vendorBytes = utf8.encode(vendor);
    out.add(_u32le(vendorBytes.length));
    out.add(vendorBytes);
    out.add(_u32le(comments.length));
    for (final comment in comments) {
      final bytes = utf8.encode(comment);
      out.add(_u32le(bytes.length));
      out.add(bytes);
    }
    final body = out.takeBytes();
    return body.length <= _maxBlockBody ? body : null;
  }

  static ({String vendor, List<String> comments})? _parseComments(
    Uint8List body,
  ) {
    try {
      final data = ByteData.sublistView(body);
      var p = 0;
      String next() {
        final length = data.getUint32(p, Endian.little);
        p += 4;
        final text = utf8.decode(
          Uint8List.sublistView(body, p, p + length),
          allowMalformed: true,
        );
        p += length;
        return text;
      }

      final vendor = next();
      final count = data.getUint32(p, Endian.little);
      p += 4;
      return (vendor: vendor, comments: [for (var i = 0; i < count; i++) next()]);
    } catch (_) {
      return null;
    }
  }

  /// A PICTURE block body: type 3 (front cover), with the image dimensions
  /// and colour depth left zero, which the format allows.
  static Uint8List _pictureBody(Uint8List image, bool isPng) {
    final mime = ascii.encode(isPng ? 'image/png' : 'image/jpeg');
    final out = BytesBuilder();
    out.add(_u32be(3));
    out.add(_u32be(mime.length));
    out.add(mime);
    out.add(_u32be(0)); // description length
    out.add(_u32be(0)); // width
    out.add(_u32be(0)); // height
    out.add(_u32be(0)); // colour depth
    out.add(_u32be(0)); // indexed colours
    out.add(_u32be(image.length));
    out.add(image);
    return out.takeBytes();
  }

  static List<int> _u32be(int v) => [
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ];

  static List<int> _u32le(int v) => [
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ];
}
