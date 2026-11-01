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
    this.settings = const [],
  });

  final String id;
  final String name;
  final String version;
  final List<String> resources;

  /// The query parameters the addon declares, with their defaults and (for
  /// a select) the values it accepts.
  final List<AddonSetting> settings;

  factory AddonManifest.fromJson(Map<String, dynamic> json) => AddonManifest(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    version: json['version']?.toString() ?? '',
    resources: [
      for (final r in (json['resources'] as List? ?? const []))
        if (r is String)
          r.toLowerCase().trim()
        else if (r is Map)
          (r['name'] ?? r['id'] ?? r['type'] ?? '')
              .toString()
              .toLowerCase()
              .trim(),
    ].where((r) => r.isNotEmpty).toList(),
    settings: _parseSettings(json),
  );

  static List<AddonSetting> _parseSettings(Map<String, dynamic> json) {
    final list = <AddonSetting>[];
    final rawSettings = json['settings'];
    if (rawSettings is List) {
      for (final s in rawSettings) {
        if (s is Map<String, dynamic>) {
          list.add(AddonSetting.fromJson(s));
        }
      }
    } else if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is Map<String, dynamic>) {
          list.add(AddonSetting.fromJson(val, key));
        } else if (val is List) {
          list.add(AddonSetting(
            key: key,
            options: [
              for (final o in val) ?AddonSetting._queryValue(o is Map ? (o['value'] ?? o['id']) : o),
            ],
          ));
        }
      }
    }

    // If no 'quality' setting was declared, check root-level quality definitions
    if (!list.any((s) => s.key == 'quality')) {
      final rootQualities = json['qualities'] ??
          json['supportedQualities'] ??
          json['supported_qualities'] ??
          json['quality'];
      if (rootQualities is List) {
        list.add(AddonSetting(
          key: 'quality',
          options: [
            for (final q in rootQualities) ?AddonSetting._queryValue(q is Map ? (q['value'] ?? q['id']) : q),
          ],
        ));
      }
    }

    return list.where((s) => s.key.isNotEmpty).toList();
  }

  bool declares(String resource) => resources.contains(resource.toLowerCase());

  /// Playable when it can find tracks; every search-capable addon resolves
  /// them through `/stream`, declared or not (BitChord reads the spec the
  /// same way). An addon that lists no resources at all is given the
  /// benefit of the doubt.
  bool get isPlayable {
    if (resources.isEmpty) return true;
    return declares('search') ||
        declares('tracks') ||
        declares('track') ||
        declares('stream') ||
        declares('catalog') ||
        declares('catalogue') ||
        declares('music');
  }

  String get displayName => name.isNotEmpty ? name : id;

  AddonSetting? setting(String key) {
    for (final s in settings) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// One query parameter an addon declares in its manifest.
class AddonSetting {
  const AddonSetting({required this.key, this.defaultValue, this.options = const []});

  final String key;
  final String? defaultValue;

  /// The values a select accepts, as they go on the wire.
  final List<String> options;

  factory AddonSetting.fromJson(Map<String, dynamic> json, [String? keyOverride]) {
    final key = keyOverride ??
        json['key']?.toString() ??
        json['id']?.toString() ??
        json['name']?.toString() ??
        '';
    final rawOptions = json['options'] ?? json['values'] ?? json['choices'];
    return AddonSetting(
      key: key,
      defaultValue: _queryValue(json['default'] ?? json['defaultValue']),
      options: [
        if (rawOptions is List)
          for (final o in rawOptions)
            ?_queryValue(o is Map ? (o['value'] ?? o['id'] ?? o['key']) : o)
      ],
    );
  }

  static String? _queryValue(Object? v) => switch (v) {
    null => null,
    String s => s.isEmpty ? null : s,
    bool b => b.toString(),
    num n => n == n.roundToDouble() ? n.toInt().toString() : n.toString(),
    _ => null,
  };
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
    this.format = '',
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

  /// What the audio is, as the addon describes it (`flac`, `mp3`…),
  /// lower-cased; empty when it didn't say.
  final String format;
  final bool isAtmos;
  final int? bitDepth;
  final int? sampleRate;
  final String? artworkUrl;

  factory AddonTrack.fromJson(Map<String, dynamic> json) {
    final quality = [
      json['audioQuality'],
      json['audio_quality'],
      json['quality'],
      json['tier'],
    ].whereType<String>().firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final modes = (json['audioModes'] as List?)?.join(' ') ?? '';
    final durationRaw = json['duration'] ??
        json['durationMs'] ??
        json['duration_ms'] ??
        json['length'];
    final durVal = durationRaw is num
        ? durationRaw.toDouble()
        : double.tryParse('$durationRaw') ?? 0;
    // Distinguish seconds (< 10000) from milliseconds (>= 10000)
    final durationMs = durVal >= 10000 ? durVal.round() : (durVal * 1000).round();

    final artistVal = json['artist'] ??
        json['artistName'] ??
        json['artist_name'] ??
        (json['artists'] is List
            ? (json['artists'] as List)
                .map((a) => a is Map ? (a['name'] ?? a['artist'] ?? '') : '$a')
                .where((s) => s.isNotEmpty)
                .join(', ')
            : null);

    final albumVal = json['album'] is Map
        ? (json['album'] as Map)['name'] ?? (json['album'] as Map)['title']
        : (json['album'] ?? json['albumName'] ?? json['album_name']);

    return AddonTrack(
      id: [json['id'], json['trackId'], json['track_id'], json['songId']]
              .whereType<Object>()
              .firstOrNull
              ?.toString() ??
          '',
      title: [json['title'], json['name'], json['trackName'], json['track_name']]
          .whereType<String>()
          .firstWhere((s) => s.isNotEmpty, orElse: () => ''),
      artist: artistVal?.toString() ?? '',
      album: albumVal?.toString() ?? '',
      duration: Duration(milliseconds: durationMs),
      audioQuality: quality.toUpperCase(),
      isAtmos: json['atmos'] == true ||
          _atmosHint.hasMatch('$quality $modes ${json['audioMode'] ?? ''}'),
      format: [
        json['format'],
        json['codec'],
        json['fileCodec'],
        json['audioCodec'],
        json['container'],
        json['encoding'],
      ]
          .whereType<String>()
          .join(' ')
          .toLowerCase()
          .trim(),
      bitDepth: findBitDepth(json),
      sampleRate: findSampleRate(json),
      artworkUrl: (json['artworkURL'] ??
              json['artworkUrl'] ??
              json['albumArtworkURL'] ??
              json['albumArtworkUrl'] ??
              json['cover'] ??
              json['image'] ??
              json['thumbnail'])
          ?.toString(),
    );
  }

  /// Whether the catalogue says this copy is actually lossless.
  /// Addons that explicitly label the tier as LOSSLESS / HI_RES match, but
  /// addons that label quality as "HIGH" or leave it blank while specifying
  /// format: "flac" are also correctly recognised as lossless.
  bool get isLossless {
    if (losslessText.hasMatch(audioQuality)) return true;
    if (losslessText.hasMatch(format)) return true;
    return bitDepth != null && bitDepth! >= 16;
  }
}

/// Words that mean a lossless copy, in any of the spellings addons use.
final RegExp losslessText = RegExp(
  r'lossless|hi[-_ ]?res|flac|alac|wav|aiff|24[-_ ]?bit',
  caseSensitive: false,
);

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

  bool get isLossless {
    final c = codec.toLowerCase();
    return c == 'flac' || c == 'alac' || c == 'wav' || c == 'aiff';
  }

  /// "FLAC 24-bit / 96 kHz", or as much of that as the addon told us.
  String get formatLabel {
    final parts = <String>[codec.isEmpty ? 'Audio' : codec.toUpperCase()];
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
