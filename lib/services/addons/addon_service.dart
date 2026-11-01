import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../canvas/canvas_artwork.dart';
import '../canvas/canvas_repository.dart';
import 'addon_client.dart';
import 'addon_models.dart';

/// A lossless copy found for a queue track, ready to play.
class AddonMatch {
  const AddonMatch({
    required this.addonName,
    required this.track,
    required this.stream,
  });

  final String addonName;
  final AddonTrack track;
  final AddonStream stream;
}

/// The installed addon (one at a time, as the settings screen offers) and
/// the lookups that turn a YouTube Music track into its lossless copy.
///
/// The addon URL carries the user's personal token, so it is kept in secure
/// storage, never in plain preferences.
class AddonService extends ChangeNotifier {
  AddonService._();
  static final AddonService instance = AddonService._();

  static const _urlKey = 'addon_base_url';
  static const _enabledKey = 'addon_enabled';
  static const _qualityKey = 'addon_quality';
  static const _nameKey = 'addon_name';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  AddonClient? _client;
  String? _name;
  bool _enabled = true;
  AddonQuality _quality = AddonQuality.lossless;
  bool _loaded = false;

  /// Settled answers per track id, misses included, so a track with no
  /// lossless copy isn't searched for again every time it plays.
  final LinkedHashMap<String, AddonMatch?> _cache = LinkedHashMap();
  final Map<String, Future<AddonMatch?>> _inFlight = {};
  static const _cacheSize = 96;

  /// Resolved stream URLs are pre-signed and expire; reuse them only briefly.
  final Map<String, DateTime> _resolvedAt = {};
  static const _streamTtl = Duration(minutes: 20);

  bool get isInstalled => _client != null;
  bool get isEnabled => _enabled && _client != null;
  String? get name => _name;
  AddonQuality get quality => _quality;

  /// Host only — the token in the path stays out of the UI.
  String? get host => _client == null ? null : Uri.parse(_client!.baseUrl).host;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final url = await _secure.read(key: _urlKey);
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      _quality = AddonQuality.fromWire(prefs.getString(_qualityKey));
      _name = prefs.getString(_nameKey);
      if (url != null && url.isNotEmpty) _client = AddonClient(url);
    } catch (e) {
      debugPrint('AddonService: load failed: $e');
    }
    notifyListeners();
  }

  /// Checks the URL serves a playable addon manifest, then keeps it.
  /// Throws [AddonException] with a message fit to show the user.
  Future<AddonManifest> install(String rawUrl) async {
    if (!AddonClient.looksValid(rawUrl)) {
      throw const AddonException('That doesn\'t look like an addon URL');
    }
    final client = AddonClient(rawUrl);
    final AddonManifest manifest;
    try {
      manifest = await client.manifest();
    } on AddonException {
      rethrow;
    } on TimeoutException {
      throw const AddonException('The addon didn\'t answer in time');
    } catch (e) {
      throw AddonException('Couldn\'t reach the addon ($e)');
    }
    if (!manifest.isPlayable) {
      throw const AddonException('This addon can\'t search and stream tracks');
    }

    await _secure.write(key: _urlKey, value: client.baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, manifest.displayName);
    await prefs.setBool(_enabledKey, true);
    _client?.close();
    _client = client;
    _name = manifest.displayName;
    _enabled = true;
    _clearCache();
    notifyListeners();
    return manifest;
  }

  Future<void> remove() async {
    await _secure.delete(key: _urlKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    _client?.close();
    _client = null;
    _name = null;
    _clearCache();
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    notifyListeners();
  }

  Future<void> setQuality(AddonQuality quality) async {
    if (quality == _quality) return;
    _quality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, quality.wire);
    _clearCache();
    notifyListeners();
  }

  void _clearCache() {
    _cache.clear();
    _resolvedAt.clear();
  }

  /// An already-resolved, still-fresh match, without touching the network.
  AddonMatch? cachedFor(Track track) {
    if (!_cache.containsKey(track.id)) return null;
    final match = _cache[track.id];
    final at = _resolvedAt[track.id];
    if (match != null &&
        (at == null || DateTime.now().difference(at) > _streamTtl)) {
      return null;
    }
    return match;
  }

  /// The lossless copy of [track], or null when the addon hasn't one (or
  /// isn't installed, enabled or reachable). Never throws.
  Future<AddonMatch?> matchFor(Track track) async {
    if (!isEnabled) return null;
    if (track.localFilePath != null || track.id.startsWith('local_')) {
      return null;
    }
    if (_cache.containsKey(track.id)) {
      final hit = _cache[track.id];
      if (hit == null) return null; // settled miss
      final fresh = cachedFor(track);
      if (fresh != null) return fresh;
      // Expired stream: re-resolve the same catalogue id, no new search.
      return _inFlight[track.id] ??= _resolve(track, known: hit.track)
          .whenComplete(() => _inFlight.remove(track.id));
    }
    return _inFlight[track.id] ??= _resolve(
      track,
    ).whenComplete(() => _inFlight.remove(track.id));
  }

  Future<AddonMatch?> _resolve(Track track, {AddonTrack? known}) async {
    final client = _client;
    if (client == null) return null;
    final quality = _quality;
    try {
      final candidate = known ?? await _findCandidate(client, track, quality);
      if (candidate == null) {
        _remember(track.id, null);
        return null;
      }
      final stream = await client.stream(candidate.id, quality: quality);
      if (!stream.isLossless) {
        _remember(track.id, null);
        return null;
      }
      final match = AddonMatch(
        addonName: _name ?? 'Addon',
        track: candidate,
        stream: stream,
      );
      _remember(track.id, match);
      return match;
    } catch (e) {
      // Network trouble isn't a verdict on the track: don't cache it.
      debugPrint('AddonService: no lossless for "${track.title}": $e');
      return null;
    }
  }

  void _remember(String id, AddonMatch? match) {
    _cache.remove(id);
    if (_cache.length >= _cacheSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _resolvedAt.remove(oldest);
    }
    _cache[id] = match;
    if (match != null) _resolvedAt[id] = DateTime.now();
  }

  Future<AddonTrack?> _findCandidate(
    AddonClient client,
    Track track,
    AddonQuality quality,
  ) async {
    final title = CanvasRepository.cleanTitle(track.title);
    final artist = CanvasRepository.cleanArtist(track.artist);
    if (title.isEmpty) return null;
    final primaryArtist = artist.split(RegExp(r'\s*(?:,|&| x |feat\.?)\s*')).first;
    AddonTrack? pick(List<AddonTrack> results) => pickBest(
      results,
      title: title,
      sourceTitle: track.title,
      artist: artist,
      album: track.album,
      duration: track.duration,
    );
    // A dubbed release usually differs from the original only by the
    // language on its album, so ask for that language by name first; the
    // plain search can rank the other languages' copies above it.
    final languages = languageTags('${track.title} ${track.album ?? ''}');
    if (languages.isNotEmpty) {
      final tagged = await client.search(
        '$primaryArtist $title ${languages.first}',
        quality: quality,
      );
      final hit = pick(tagged);
      if (hit != null) return hit;
    }
    return pick(await client.search('$primaryArtist $title', quality: quality));
  }

  /// The search hit that is the same recording as what's playing, or null.
  ///
  /// A different recording is worse than no upgrade — swapping a live take,
  /// a remix or another language's dub in mid-song is jarring — so the bar
  /// is: same title once normalised, the same take markers ("Remix",
  /// "Live"…) and the same language, every artist credited, a duration
  /// within a few seconds when both are known, and actually lossless. Atmos
  /// copies are left out; they're a different mix, not a better copy.
  ///
  /// Language follows BitChord's rule for takes: both directions must
  /// agree. Film songs are released once per language with the same title,
  /// composer and near-identical runtime, the only difference being a tag on
  /// the album or title ("Kanguva (Telugu)"). An untagged track only takes
  /// untagged copies, which are the original, and a tagged one only takes
  /// copies sharing its tag. [sourceTitle] is the title before cleaning,
  /// which can still hold a tag inside "(From "Film (Tamil)")".
  @visibleForTesting
  static AddonTrack? pickBest(
    List<AddonTrack> results, {
    required String title,
    String? sourceTitle,
    required String artist,
    String? album,
    Duration duration = Duration.zero,
  }) {
    final wantTitle = CanvasArtwork.normalizeForMatch(title);
    // A title in a script normalisation drops would match every other one.
    if (wantTitle.isEmpty) return null;
    final wantAlbum = album == null ? '' : CanvasArtwork.normalizeForMatch(album);
    final wantTakes = takeMarkers(sourceTitle ?? title);
    final wantLanguages = languageTags('${sourceTitle ?? title} ${album ?? ''}');
    AddonTrack? best;
    var bestScore = -1;
    for (final hit in results) {
      if (hit.isAtmos || !hit.isLossless) continue;
      if (CanvasArtwork.normalizeForMatch(hit.title) != wantTitle) continue;
      if (!setEquals(takeMarkers(hit.title), wantTakes)) continue;
      final languages = languageTags('${hit.title} ${hit.album}');
      if (wantLanguages.isEmpty
          ? languages.isNotEmpty
          : !languages.any(wantLanguages.contains)) {
        continue;
      }
      if (!CanvasArtwork.allCredited(
        artist,
        CanvasArtwork.splitArtists(hit.artist),
      )) {
        continue;
      }
      var score = 10;
      if (duration > Duration.zero && hit.duration > Duration.zero) {
        final diff = (duration - hit.duration).inMilliseconds.abs();
        if (diff > 4000) continue; // another edit of the song
        score += diff <= 1500 ? 10 : 4;
      }
      if (wantAlbum.isNotEmpty &&
          CanvasArtwork.normalizeForMatch(hit.album) == wantAlbum) {
        score += 6;
      }
      if (hit.audioQuality.contains('HI_RES')) score += 2;
      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }
    return best;
  }

  static final _languageWord = RegExp(
    r'\b(tamil|telugu|hindi|malayalam|kannada|bengali|bangla|marathi|punjabi|'
    r'gujarati|odia|bhojpuri|urdu|sanskrit|english|spanish|portuguese|french|'
    r'german|italian|korean|japanese|chinese|mandarin|cantonese|arabic|'
    r'turkish|russian|indonesian|thai|filipino|tagalog)\b',
  );

  /// The languages a title or album names ("Kanguva (Telugu)", "Song -
  /// Hindi Version"). Bengali and Bangla are one language.
  @visibleForTesting
  static Set<String> languageTags(String text) => {
    for (final m in _languageWord.allMatches(CanvasArtwork.foldDiacritics(text).toLowerCase()))
      m[1] == 'bangla' ? 'bengali' : m[1]!,
  };

  static final _takeWord = RegExp(
    r'\b(remix|rmx|live|acoustic|unplugged|instrumental|karaoke|reprise|'
    r'cover|demo|lofi|slowed|sped|reverb|nightcore|acapella|mashup|medley)\b',
  );

  /// The take markers ("Remix", "Live", "Lofi"…) in the bracketed or
  /// dash-separated asides of a title. The title proper is left alone, so a
  /// song called "Let Me Live" isn't read as a live take.
  @visibleForTesting
  static Set<String> takeMarkers(String title) {
    final text = CanvasArtwork.foldDiacritics(title).toLowerCase();
    final asides = [
      for (final m in RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]').allMatches(text)) m[1]!,
      ...text.split(RegExp(r'\s[-–—]\s')).skip(1),
    ].join(' ').replaceAll('lo-fi', 'lofi');
    return {for (final m in _takeWord.allMatches(asides)) m[1]!};
  }
}
