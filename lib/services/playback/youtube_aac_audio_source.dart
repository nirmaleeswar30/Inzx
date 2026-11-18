import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'youtube_mp4_fix.dart';

/// A YouTube AAC stream for AVPlayer (iOS), with [YouTubeMp4Fix] applied to
/// its opening on the way through, so the track reports its real length.
///
/// Served by just_audio's local proxy, which is also how a stream with
/// request headers (the client's user agent) reaches AVPlayer on iOS anyway.
/// Every range AVPlayer asks for is fetched with the same headers; a range
/// that starts inside the opening is fetched from byte 0 so the patch can
/// see the whole `moov`, and the bytes before the range are dropped.
// ignore: experimental_member_use
class YouTubeAacAudioSource extends StreamAudioSource {
  YouTubeAacAudioSource(
    this.uri, {
    Map<String, String>? headers,
    this.knownLength,
    super.tag,
  }) : headers = headers ?? const {};

  final Uri uri;
  final Map<String, String> headers;

  /// The file's size when the player response gave it.
  final int? knownLength;

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);

  int? _sourceLength;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final patchHead = from < YouTubeMp4Fix.headWindow;
    final fetchFrom = patchHead ? 0 : from;
    final request = await _client.getUrl(uri);
    headers.forEach(request.headers.set);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$fetchFrom-${end != null ? end - 1 : ''}',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.partialContent &&
        response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    // A 200 means the whole file, wherever the range asked to start.
    final servedFrom = response.statusCode == HttpStatus.ok ? 0 : fetchFrom;
    final total = _totalLength(response) ?? _sourceLength ?? knownLength;
    if (total != null) _sourceLength = total;
    final endExclusive = end ?? total;

    final Stream<List<int>> body = patchHead || servedFrom < from
        ? _patched(response, skip: from - servedFrom, patch: servedFrom == 0)
        : response;

    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: endExclusive != null ? endExclusive - from : null,
      offset: from,
      stream: body,
      contentType: 'audio/mp4',
      rangeRequestsSupported: true,
    );
  }

  static int? _totalLength(HttpClientResponse response) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    if (range != null) {
      final slash = range.lastIndexOf('/');
      if (slash >= 0) {
        final total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null) return total;
      }
    }
    if (response.statusCode == HttpStatus.ok && response.contentLength > 0) {
      return response.contentLength;
    }
    return null;
  }

  /// Holds back the opening until its `moov` is complete, patches it, then
  /// passes everything on, dropping the first [skip] bytes.
  static Stream<List<int>> _patched(
    Stream<List<int>> source, {
    required int skip,
    required bool patch,
  }) async* {
    var toSkip = skip;
    final head = BytesBuilder(copy: false);
    var holding = patch;

    Iterable<List<int>> emit(List<int> chunk) sync* {
      if (toSkip >= chunk.length) {
        toSkip -= chunk.length;
        return;
      }
      if (toSkip > 0) {
        final rest = chunk.sublist(toSkip);
        toSkip = 0;
        yield rest;
      } else {
        yield chunk;
      }
    }

    await for (final chunk in source) {
      if (!holding) {
        yield* Stream.fromIterable(emit(chunk));
        continue;
      }
      head.add(chunk);
      final bytes = head.toBytes();
      final end = YouTubeMp4Fix.moovEnd(bytes);
      if (end == -1 && bytes.length < YouTubeMp4Fix.headWindow) continue;
      if (end >= 0) YouTubeMp4Fix.patchDurations(bytes);
      holding = false;
      head.clear();
      yield* Stream.fromIterable(emit(bytes));
    }
    if (holding) {
      // The whole response was shorter than the opening it was waiting for.
      final bytes = head.toBytes();
      if (YouTubeMp4Fix.moovEnd(bytes) >= 0) YouTubeMp4Fix.patchDurations(bytes);
      yield* Stream.fromIterable(emit(Uint8List.fromList(bytes)));
    }
  }
}
