import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// The files that make up one audio track of a DASH stream, in play order.
class DashTrack {
  const DashTrack({required this.segments, this.codecs = ''});

  /// Initialization segment first (when there is one), then media segments.
  final List<Uri> segments;
  final String codecs;
}

/// Reads the on-demand MPD an addon hands back, far enough to download the
/// stream whole: the player handles these natively, but a download needs the
/// list of files spelled out.
class DashManifest {
  static const int _maxSegments = 20000;

  /// Fetches [url] (or decodes it, when it's a `data:` URI holding the MPD)
  /// and reads it. Throws [FormatException] if it can't be used.
  static Future<DashTrack> load(String url, http.Client client) async {
    final uri = Uri.parse(url);
    if (uri.isScheme('data')) {
      final data = uri.data;
      if (data == null) throw const FormatException('Empty manifest');
      return parse(data.contentAsString());
    }
    final response = await client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('Manifest HTTP ${response.statusCode}', uri);
    }
    return parse(response.body, baseUri: uri);
  }

  static DashTrack parse(String xml, {Uri? baseUri}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw FormatException('Unreadable manifest: ${e.message}');
    }
    final mpd = document.rootElement;
    if (mpd.localName != 'MPD') {
      throw const FormatException('Not a DASH manifest');
    }
    final period = _child(mpd, 'Period');
    if (period == null) throw const FormatException('Manifest has no period');
    if (_children(period, 'AdaptationSet').isEmpty) {
      throw const FormatException('Manifest has no audio');
    }

    final presentation = _seconds(
      period.getAttribute('duration') ??
          mpd.getAttribute('mediaPresentationDuration'),
    );

    XmlElement? bestSet;
    XmlElement? bestRep;
    var bestScore = -1;
    for (final set in _children(period, 'AdaptationSet')) {
      if (_child(set, 'ContentProtection') != null) continue;
      for (final rep in _children(set, 'Representation')) {
        if (_child(rep, 'ContentProtection') != null) continue;
        final mime =
            rep.getAttribute('mimeType') ??
            set.getAttribute('mimeType') ??
            set.getAttribute('contentType') ??
            '';
        if (mime.isNotEmpty && !mime.startsWith('audio')) continue;
        final codecs =
            (rep.getAttribute('codecs') ?? set.getAttribute('codecs') ?? '')
                .toLowerCase();
        // Lossless first, then the richest of those.
        final lossless = codecs.contains('flac') || codecs.contains('alac');
        final bandwidth = int.tryParse(rep.getAttribute('bandwidth') ?? '') ?? 0;
        final score = (lossless ? 1 << 40 : 0) + bandwidth;
        if (score > bestScore) {
          bestScore = score;
          bestSet = set;
          bestRep = rep;
        }
      }
    }
    if (bestSet == null || bestRep == null) {
      throw const FormatException('Manifest has no playable audio');
    }

    var base = baseUri;
    for (final element in [mpd, period, bestSet, bestRep]) {
      final text = _child(element, 'BaseURL')?.innerText.trim();
      if (text == null || text.isEmpty) continue;
      base = base?.resolve(text) ?? Uri.parse(text);
    }
    Uri resolve(String path) => base?.resolve(path) ?? Uri.parse(path);

    final representationId = bestRep.getAttribute('id') ?? '';
    final bandwidth = bestRep.getAttribute('bandwidth') ?? '';
    final codecs =
        bestRep.getAttribute('codecs') ?? bestSet.getAttribute('codecs') ?? '';

    final template =
        _child(bestRep, 'SegmentTemplate') ??
        _child(bestSet, 'SegmentTemplate') ??
        _child(period, 'SegmentTemplate');
    if (template != null) {
      final parentTemplate = identical(template, _child(bestRep, 'SegmentTemplate'))
          ? _child(bestSet, 'SegmentTemplate')
          : null;
      String? attribute(String name) =>
          template.getAttribute(name) ?? parentTemplate?.getAttribute(name);

      String fill(String pattern, {int? number, int? time}) => _fillTemplate(
        pattern,
        representationId: representationId,
        bandwidth: bandwidth,
        number: number,
        time: time,
      );

      final media = attribute('media');
      if (media == null || media.isEmpty) {
        throw const FormatException('Segment template has no media');
      }
      final segments = <Uri>[];
      final initialization = attribute('initialization');
      if (initialization != null && initialization.isNotEmpty) {
        segments.add(resolve(fill(initialization)));
      }

      final timescale = int.tryParse(attribute('timescale') ?? '') ?? 1;
      final startNumber = int.tryParse(attribute('startNumber') ?? '') ?? 1;
      final timeline =
          _child(template, 'SegmentTimeline') ??
          (parentTemplate == null
              ? null
              : _child(parentTemplate, 'SegmentTimeline'));

      if (timeline != null) {
        var number = startNumber;
        var time = 0;
        final entries = _children(timeline, 'S');
        final totalTicks = presentation == null
            ? null
            : (presentation * timescale).ceil();
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final start = int.tryParse(entry.getAttribute('t') ?? '');
          if (start != null) time = start;
          final duration = int.tryParse(entry.getAttribute('d') ?? '') ?? 0;
          if (duration <= 0) throw const FormatException('Bad segment timeline');
          var repeat = int.tryParse(entry.getAttribute('r') ?? '') ?? 0;
          if (repeat < 0) {
            // "Until the next entry, or the end of the period."
            final next = i + 1 < entries.length
                ? int.tryParse(entries[i + 1].getAttribute('t') ?? '')
                : totalTicks;
            if (next == null) throw const FormatException('Open-ended timeline');
            repeat = ((next - time) / duration).ceil() - 1;
          }
          for (var r = 0; r <= repeat; r++) {
            segments.add(resolve(fill(media, number: number, time: time)));
            number++;
            time += duration;
            if (segments.length > _maxSegments) {
              throw const FormatException('Too many segments');
            }
          }
        }
      } else {
        final duration = int.tryParse(attribute('duration') ?? '');
        if (duration == null || duration <= 0 || presentation == null) {
          throw const FormatException('Segment count unknown');
        }
        final count = min(
          (presentation * timescale / duration).ceil(),
          _maxSegments,
        );
        for (var i = 0; i < count; i++) {
          segments.add(
            resolve(
              fill(media, number: startNumber + i, time: i * duration),
            ),
          );
        }
      }
      return DashTrack(segments: segments, codecs: codecs);
    }

    final list =
        _child(bestRep, 'SegmentList') ?? _child(bestSet, 'SegmentList');
    if (list != null) {
      final segments = <Uri>[];
      final init = _child(list, 'Initialization')?.getAttribute('sourceURL');
      if (init != null && init.isNotEmpty) segments.add(resolve(init));
      for (final entry in _children(list, 'SegmentURL')) {
        final media = entry.getAttribute('media');
        if (media != null && media.isNotEmpty) segments.add(resolve(media));
      }
      if (segments.isEmpty) throw const FormatException('Empty segment list');
      return DashTrack(segments: segments, codecs: codecs);
    }

    // One self-indexed file behind the BaseURL.
    if (base != null && _child(bestRep, 'BaseURL') != null) {
      return DashTrack(segments: [base], codecs: codecs);
    }
    throw const FormatException('Manifest lists no segments');
  }

  static String _fillTemplate(
    String pattern, {
    required String representationId,
    required String bandwidth,
    int? number,
    int? time,
  }) {
    return pattern.replaceAllMapped(RegExp(r'\$([A-Za-z]*)(%0(\d+)d)?\$'), (m) {
      String pad(int value) => m[3] == null
          ? '$value'
          : '$value'.padLeft(int.parse(m[3]!), '0');
      return switch (m[1]) {
        '' => r'$',
        'RepresentationID' => representationId,
        'Bandwidth' => bandwidth,
        'Number' when number != null => pad(number),
        'Time' when time != null => pad(time),
        _ => m[0]!,
      };
    });
  }

  /// An ISO 8601 duration ("PT3M25.5S") in seconds.
  static double? _seconds(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    double part(int group) => double.tryParse(match[group] ?? '') ?? 0;
    return part(1) * 86400 + part(2) * 3600 + part(3) * 60 + part(4);
  }

  static XmlElement? _child(XmlElement parent, String name) =>
      _children(parent, name).firstOrNull;

  static List<XmlElement> _children(XmlElement parent, String name) => parent
      .childElements
      .where((e) => e.localName == name)
      .toList();
}
