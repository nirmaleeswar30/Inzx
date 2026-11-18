import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../addons/dash_manifest.dart';
import 'youtube_mp4_fix.dart';

/// A DASH stream (an addon's lossless) for AVPlayer (iOS), as one
/// fragmented MP4 file.
///
/// AVPlayer can't play DASH. BitChord-iOS's answer, ported here: the init
/// segment followed by each media segment's `moof`/`mdat` *is* a fragmented
/// MP4 file, so this lays that file out without downloading it (the init
/// segment in hand; for each media segment, its size and where its `moof`
/// starts, from one small ranged request each) and serves it through
/// just_audio's local proxy. Each byte range AVPlayer asks for is fetched
/// from the segment it falls in. A playlist (HLS) would have been simpler,
/// but iOS runs no audio tap on HLS, so the equaliser, AutoEQ, loudness and
/// Automix's filters would all have stopped at lossless songs.
// ignore: experimental_member_use
class DashFmp4AudioSource extends StreamAudioSource {
  DashFmp4AudioSource(this.manifestUrl, {super.tag, DashFetcher? fetcher})
      : _fetcher = fetcher ?? HttpDashFetcher();

  /// The manifest's URL, or a `data:` URI holding it.
  final String manifestUrl;
  final DashFetcher _fetcher;
  Future<DashFileLayout>? _layout;

  /// The file this stream is laid out as (built on the first request).
  Future<DashFileLayout> layout() => _layout ??= DashFileLayout.build(manifestUrl, _fetcher).catchError(
        (Object e, StackTrace s) {
          _layout = null; // a later request tries again
          return Future<DashFileLayout>.error(e, s);
        },
      );

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final file = await layout();
    final total = file.length;
    final from = (start ?? 0).clamp(0, total);
    final to = (end ?? total).clamp(from, total);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: to - from,
      offset: from,
      stream: file.read(from, to, _fetcher),
      contentType: 'audio/mp4',
      rangeRequestsSupported: true,
    );
  }
}

/// One media segment's place in the file.
class DashPart {
  const DashPart({required this.url, required this.skip, required this.length, required this.offset});
  final Uri url;

  /// Bytes at the segment's start that are left out (`styp`, `sidx`: they
  /// describe the segment as a file of its own and mean nothing mid-file).
  final int skip;

  /// Bytes of the segment that are in the file.
  final int length;

  /// Where they start in the file.
  final int offset;
}

/// The fragmented MP4 file a DASH stream makes: [init], then [parts].
class DashFileLayout {
  DashFileLayout(this.init, this.parts)
      : length = init.length + parts.fold<int>(0, (sum, p) => sum + p.length);

  final Uint8List init;
  final List<DashPart> parts;
  final int length;

  static const int _probeBytes = 8192;
  static const int _probesAtOnce = 8;

  /// Reads the manifest at [manifestUrl] and measures its segments.
  static Future<DashFileLayout> build(String manifestUrl, DashFetcher fetcher) async {
    final uri = Uri.parse(manifestUrl);
    final DashTrack track;
    if (uri.isScheme('data')) {
      final data = uri.data;
      if (data == null) throw const FormatException('Empty manifest');
      track = DashManifest.parse(data.contentAsString());
    } else {
      track = DashManifest.parse(utf8.decode(await fetcher.whole(uri), allowMalformed: true), baseUri: uri);
    }
    if (track.segments.isEmpty) throw const FormatException('Manifest lists no segments');

    if (track.singleFile) {
      final probe = await fetcher.head(track.segments.first, 1);
      return DashFileLayout(Uint8List(0), [
        DashPart(url: track.segments.first, skip: 0, length: probe.total, offset: 0),
      ]);
    }
    if (!track.hasInit) throw const FormatException('Segments without an initialization segment');

    final init = await fetcher.whole(track.segments.first);
    // As for YouTube's AAC: AVFoundation then measures the length from the
    // fragments rather than trusting the opening's figures.
    YouTubeMp4Fix.patchDurations(init);

    final media = track.segments.sublist(1);
    final sizes = List<({int skip, int length})?>.filled(media.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < media.length) {
        final i = next++;
        final probe = await fetcher.head(media[i], _probeBytes);
        final skip = moofOffset(probe.head);
        sizes[i] = (skip: skip, length: probe.total - skip);
      }
    }

    await Future.wait([for (var w = 0; w < min(_probesAtOnce, media.length); w++) worker()]);

    final parts = <DashPart>[];
    var offset = init.length;
    for (var i = 0; i < media.length; i++) {
      final size = sizes[i]!;
      parts.add(DashPart(url: media[i], skip: size.skip, length: size.length, offset: offset));
      offset += size.length;
    }
    return DashFileLayout(init, parts);
  }

  /// Where a media segment's `moof` starts: past the leading boxes that
  /// only describe the segment as a file of its own. 0 (keep it all) when
  /// [head] doesn't reach one.
  static int moofOffset(Uint8List head) {
    const leading = {'styp', 'sidx', 'ssix', 'prft', 'emsg', 'free', 'skip'};
    final view = ByteData.sublistView(head);
    var at = 0;
    while (at + 8 <= head.length) {
      var size = view.getUint32(at);
      final type = String.fromCharCodes(head, at + 4, at + 8);
      if (type == 'moof') return at;
      if (!leading.contains(type)) return at;
      if (size == 1) {
        if (at + 16 > head.length) return 0;
        size = view.getUint64(at + 8);
      }
      if (size < 8) return 0;
      at += size;
    }
    return 0;
  }

  /// Index of the part holding file byte [position] (at or past [init]).
  int partAt(int position) {
    var lo = 0, hi = parts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (parts[mid].offset <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// File bytes [from] to [to] (exclusive), fetched part by part.
  Stream<List<int>> read(int from, int to, DashFetcher fetcher) async* {
    var position = from;
    if (position < init.length && position < to) {
      final end = min(to, init.length);
      yield Uint8List.sublistView(init, position, end);
      position = end;
    }
    if (parts.isEmpty) return;
    var i = partAt(position);
    while (position < to && i < parts.length) {
      final part = parts[i];
      final a = position - part.offset;
      final b = min(to, part.offset + part.length) - part.offset;
      if (b > a) yield* _rangeWithRetry(fetcher, part.url, part.skip + a, part.skip + b);
      position = part.offset + b;
      i++;
    }
  }

  /// A segment range; a read that fails part-way is asked again from the
  /// byte it reached.
  static Stream<List<int>> _rangeWithRetry(DashFetcher fetcher, Uri url, int from, int to) async* {
    var at = from;
    for (var attempt = 1; ; attempt++) {
      try {
        await for (final chunk in fetcher.range(url, at, to)) {
          final room = to - at;
          if (room <= 0) break;
          final take = chunk.length > room ? chunk.sublist(0, room) : chunk;
          at += take.length;
          yield take;
        }
        if (at >= to) return;
        throw const HttpException('Segment ended early');
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }
}

/// The network side of [DashFmp4AudioSource] (replaced in tests).
abstract class DashFetcher {
  Future<Uint8List> whole(Uri uri);

  /// The first [bytes] of [uri] (fewer when it's shorter) and its size.
  Future<({Uint8List head, int total})> head(Uri uri, int bytes);

  /// Bytes [from] to [to] (exclusive) of [uri].
  Stream<List<int>> range(Uri uri, int from, int to);
}

class HttpDashFetcher implements DashFetcher {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);

  Future<HttpClientResponse> _get(Uri uri, {String? range}) async {
    final request = await _client.getUrl(uri);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response;
  }

  @override
  Future<Uint8List> whole(Uri uri) async {
    final response = await _get(uri);
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add).timeout(const Duration(seconds: 60));
    return builder.toBytes();
  }

  @override
  Future<({Uint8List head, int total})> head(Uri uri, int bytes) async {
    final response = await _get(uri, range: 'bytes=0-${bytes - 1}');
    final builder = BytesBuilder(copy: false);
    int? total;
    if (response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      total = int.tryParse(range.substring(range.lastIndexOf('/') + 1).trim());
    } else if (response.contentLength >= 0) {
      total = response.contentLength;
    }
    // A server that ignores ranges sends it all; keep only the opening.
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      builder.add(chunk);
      if (total != null && builder.length >= bytes) break;
    }
    final head = builder.toBytes();
    total ??= head.length;
    return (head: head.length > bytes ? Uint8List.sublistView(head, 0, bytes) : head, total: total);
  }

  @override
  Stream<List<int>> range(Uri uri, int from, int to) async* {
    final response = await _get(uri, range: 'bytes=$from-${to - 1}');
    // A 200 is the whole segment: drop what comes before the range.
    var skip = response.statusCode == HttpStatus.ok ? from : 0;
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (skip >= chunk.length) {
        skip -= chunk.length;
        continue;
      }
      yield skip > 0 ? chunk.sublist(skip) : chunk;
      skip = 0;
    }
  }
}
