/// Wire models for the addon HTTP protocol (LastWave-compatible):
///
///  - `GET {base}/manifest.json`
///  - `GET {base}/search?q=…&quality=…&atmos=…`
///  - `GET {base}/stream/{id}?quality=…&atmos=…`
///
/// Addons are written by different people and name the same field half a
/// dozen ways (`bitDepth`, `bit_depth`, `bitsPerSample`, nested under
/// `metadata` or `audio`…), so the audio-format fields are read by a lenient
/// search over the decoded JSON rather than a fixed schema.
library;

/// Quality tiers an addon can be asked for. The names are the protocol's own
/// query values.
enum AddonQuality {
  /// CD quality: 16-bit / 44.1 kHz FLAC.
  lossless('lossless', 'Lossless', '16-bit / 44.1 kHz FLAC'),

  /// Up to 24-bit / 192 kHz FLAC where the catalogue has it.
  hiRes('hi_res', 'Hi-Res Lossless', 'Up to 24-bit / 192 kHz FLAC');

  const AddonQuality(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String description;

  static AddonQuality fromWire(String? value) => AddonQuality.values
      .firstWhere((q) => q.wire == value, orElse: () => AddonQuality.lossless);
}

class AddonManifest {
  const AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.resources,
  });

  final String id;
  final String name;
  final String version;
  final List<String> resources;

  factory AddonManifest.fromJson(Map<String, dynamic> json) => AddonManifest(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    version: json['version']?.toString() ?? '',
    resources: (json['resources'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const [],
  );

  bool declares(String resource) => resources.contains(resource.toLowerCase());

  /// Playable when it can both find tracks and resolve them. An addon that
  /// lists no resources at all is given the benefit of the doubt.
  bool get isPlayable =>
      resources.isEmpty || (declares('search') && declares('stream'));

  String get displayName => name.isNotEmpty ? name : id;
}

class AddonTrack {
  const AddonTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.audioQuality,
    required this.isAtmos,
    this.bitDepth,
    this.sampleRate,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;

  /// The catalogue's own tier name, upper-cased: LOSSLESS, HI_RES_LOSSLESS,
  /// HIGH, LOW…
  final String audioQuality;
  final bool isAtmos;
  final int? bitDepth;
  final int? sampleRate;
  final String? artworkUrl;

  factory AddonTrack.fromJson(Map<String, dynamic> json) {
    final quality = [
      json['audioQuality'],
      json['audio_quality'],
      json['quality'],
    ].whereType<String>().firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final modes = (json['audioModes'] as List?)?.join(' ') ?? '';
    final durationRaw = json['duration'];
    return AddonTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      duration: Duration(
        milliseconds: ((durationRaw is num
                    ? durationRaw.toDouble()
                    : double.tryParse('$durationRaw') ?? 0) *
                1000)
            .round(),
      ),
      audioQuality: quality.toUpperCase(),
      isAtmos: json['atmos'] == true ||
          _atmosHint.hasMatch('$quality $modes ${json['audioMode'] ?? ''}'),
      bitDepth: findBitDepth(json),
      sampleRate: findSampleRate(json),
      artworkUrl: (json['artworkURL'] ?? json['artworkUrl'])?.toString(),
    );
  }

  /// Whether the catalogue says this copy is actually lossless. Search
  /// results report the tier the *file* has, which for some editions is
  /// only HIGH or LOW even when lossless was asked for.
  bool get isLossless =>
      audioQuality.contains('LOSSLESS') ||
      audioQuality.contains('HI_RES') ||
      (bitDepth != null && bitDepth! >= 16 && audioQuality.isEmpty);
}

/// A resolved, playable stream.
class AddonStream {
  const AddonStream({
    required this.url,
    required this.isDash,
    required this.codec,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
  });

  /// A DASH manifest (`.mpd`) or a direct file URL.
  final String url;
  final bool isDash;
  final String codec;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;

  bool get isLossless =>
      codec.toLowerCase() == 'flac' || codec.toLowerCase() == 'alac';

  /// "FLAC 24-bit / 96 kHz", or as much of that as the addon told us.
  String get formatLabel {
    final parts = <String>[codec.toUpperCase()];
    final depth = bitDepth;
    final rate = sampleRate;
    if (depth != null && rate != null) {
      parts.add('$depth-bit / ${_khz(rate)} kHz');
    } else if (rate != null) {
      parts.add('${_khz(rate)} kHz');
    }
    return parts.join(' ');
  }

  static String _khz(int hz) {
    final k = hz / 1000;
    return k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
  }
}

final RegExp _atmosHint = RegExp(
  r'atmos|dolby|eac3[_-]?joc|ec-?3',
  caseSensitive: false,
);

const _nestedKeys = [
  'metadata',
  'meta',
  'mediaMetadata',
  'media_metadata',
  'audio',
  'stream',
  'data',
  'info',
  'streamInfo',
  'stream_info',
];

/// Bit depth from wherever the addon put it, or from a "24-bit/96" style
/// quality string. Null when nothing says.
int? findBitDepth(Object? node, [int depth = 0]) {
  if (node == null || depth > 4) return null;
  if (node is num) {
    final v = node.toInt();
    return v >= 8 && v <= 32 ? v : null;
  }
  if (node is String) return depthFromText(node);
  if (node is Map) {
    for (final key in const [
      'bitDepth',
      'bit_depth',
      'bitsPerSample',
      'bits_per_sample',
      'bitType',
      'bit_type',
      'depth',
      'bits',
    ]) {
      final v = node[key];
      if (v is num) {
        final found = findBitDepth(v, depth + 1);
        if (found != null) return found;
      } else if (v is String) {
        final found = int.tryParse(v.trim()) ?? depthFromText(v);
        if (found != null && found >= 8 && found <= 32) return found;
      }
    }
    for (final key in _nestedKeys) {
      final v = node[key];
      if (v is Map) {
        final found = findBitDepth(v, depth + 1);
        if (found != null) return found;
      }
    }
  }
  return null;
}

/// Sample rate in Hz, reading "96", "96 kHz", "96000" and nested objects.
int? findSampleRate(Object? node, [int depth = 0]) {
  if (node == null || depth > 4) return null;
  if (node is num) {
    final v = node.toDouble();
    if (v <= 0) return null;
    return (v < 1000 ? v * 1000 : v).round();
  }
  if (node is String) return rateFromText(node);
  if (node is Map) {
    for (final key in const [
      'sampleRate',
      'sample_rate',
      'samplingRate',
      'sampling_rate',
      'clockRate',
      'clock_rate',
    ]) {
      final v = node[key];
      if (v is num) {
        final found = findSampleRate(v, depth + 1);
        if (found != null) return found;
      } else if (v is String) {
        final n = double.tryParse(v.trim());
        if (n != null && n > 0) return (n < 1000 ? n * 1000 : n).round();
        final found = rateFromText(v);
        if (found != null) return found;
      }
    }
    for (final key in _nestedKeys) {
      final v = node[key];
      if (v is Map) {
        final found = findSampleRate(v, depth + 1);
        if (found != null) return found;
      }
    }
  }
  return null;
}

int? depthFromText(String text) {
  final pair = RegExp(r'(?:^|\D)(16|24|32)\s*[-_ ]?bit', caseSensitive: false)
          .firstMatch(text) ??
      RegExp(r'(?:^|\D)(16|24|32)\s*/\s*\d').firstMatch(text);
  if (pair != null) return int.parse(pair.group(1)!);
  final upper = text.toUpperCase();
  if (upper.contains('HI_RES') || upper.contains('HI-RES')) return 24;
  return null;
}

int? rateFromText(String text) {
  final khz = RegExp(
    r'\b(44\.1|48|88\.2|96|176\.4|192|352\.8|384)\s*k(?:hz)?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (khz != null) return (double.parse(khz.group(1)!) * 1000).round();
  final hz = RegExp(
    r'\b(44100|48000|88200|96000|176400|192000|352800|384000)\b',
  ).firstMatch(text);
  if (hz != null) return int.parse(hz.group(1)!);
  final slash = RegExp(r'(?:16|24|32)\s*[-_ ]?(?:bit)?\s*/\s*(\d{2,3}(?:\.\d)?)')
      .firstMatch(text);
  if (slash != null) return (double.parse(slash.group(1)!) * 1000).round();
  return null;
}
