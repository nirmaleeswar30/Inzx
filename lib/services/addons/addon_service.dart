import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../audio_output_service.dart';
import '../canvas/canvas_artwork.dart';
import '../canvas/canvas_repository.dart';
import '../secure_store.dart';
import 'addon_client.dart';
import 'addon_models.dart';

/// A lossless or Atmos copy found for a queue track, ready to play.
class AddonMatch {
  const AddonMatch({
    required this.addonName,
    required this.track,
    required this.stream,
    this.addonId,
  });

  final String addonName;
  final String? addonId;
  final AddonTrack track;
  final AddonStream stream;
}

/// An installed addon source with its credentials, quality preference, and active state.
class AddonEntry {
  AddonEntry({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.enabled = true,
    this.quality = AddonQuality.lossless,
    AddonClient? client,
  }) : client = client ?? AddonClient(baseUrl);

  final String id;
  String name;
  final String baseUrl;
  bool enabled;
  AddonQuality quality;
  final AddonClient client;

  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'enabled': enabled,
    'quality': quality.wire,
  };

  factory AddonEntry.fromJson(Map<String, dynamic> json) => AddonEntry(
    id: json['id'] as String? ?? json['baseUrl'] as String,
    name: json['name'] as String? ?? 'Addon',
    baseUrl: json['baseUrl'] as String,
    enabled: json['enabled'] as bool? ?? true,
    quality: AddonQuality.fromWire(json['quality'] as String?),
  );

  void close() {
    client.close();
  }
}

/// The installed addons (tried in priority order, like BitChord) and
/// the lookups that turn a YouTube Music track into its lossless copy.
///
/// Addon URLs carry user personal tokens, so they are kept in secure
/// storage, never in plain preferences.
class AddonService extends ChangeNotifier {
  AddonService._();
  static final AddonService instance = AddonService._();

  static const _urlKey = 'addon_base_url';
  static const _enabledKey = 'addon_enabled';
  static const _qualityKey = 'addon_quality';
  static const _nameKey = 'addon_name';
  static const _sourcesKey = 'addon_sources_list_v1';

  final SecureStore _secure = SecureStore.instance;

  final List<AddonEntry> _addons = [];
  bool _loaded = false;
  bool _allowAtmos = false;
  bool? _testAtmosSupport;
  int _cacheRevision = 0;
  final Set<String> _failedAtmos = <String>{};

  Future<void> _refreshAtmosPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getBool(AudioOutputService.preferAtmosKey) ??
        AudioOutputService.preferAtmosDefault;
    final allowed = preferred &&
        (_testAtmosSupport ??
            (await AudioOutputService.describe())?.atmosSupported ??
            false);
    if (_allowAtmos == allowed) return;
    _allowAtmos = allowed;
    _failedAtmos.clear();
    _clearCache();
  }

  /// A failed Atmos load must retry the stereo mix, not the same URL.
  void rejectAtmosFor(Track track) {
    _failedAtmos.add(track.id);
    if (_failedAtmos.length > _cacheSize) {
      _failedAtmos.remove(_failedAtmos.first);
    }
    _cache.remove(track.id);
    _resolvedAt.remove(track.id);
  }

  Future<void> setPreferAtmos(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(
      AudioOutputService.preferAtmosKey,
      enabled,
    );
    await _refreshAtmosPolicy();
    notifyListeners();
  }

  /// Recheck the route before using an Atmos copy prefetched on another output.
  Future<bool> canPlayAtmos(Track track) async {
    await _refreshAtmosPolicy();
    return _allowAtmos && !_failedAtmos.contains(track.id);
  }

  /// Settled answers per track id, misses included, so a track with no
  /// lossless copy isn't searched for again every time it plays.
  final LinkedHashMap<String, AddonMatch?> _cache = LinkedHashMap();
  final Map<String, Future<AddonMatch?>> _inFlight = {};
  static const _cacheSize = 96;

  /// Resolved stream URLs are pre-signed and expire; reuse them only briefly.
  final Map<String, DateTime> _resolvedAt = {};
  static const _streamTtl = Duration(minutes: 20);

  bool get isInstalled => _addons.isNotEmpty;
  bool get isEnabled => _addons.any((a) => a.enabled);
  String? get name => _addons.firstOrNull?.name;
  AddonQuality get quality =>
      _addons.firstOrNull?.quality ?? AddonQuality.lossless;

  /// Host only — the token in the path stays out of the UI.
  String? get host => _addons.firstOrNull?.host;

  /// All installed addon entries in priority order.
  List<AddonEntry> get addons => List.unmodifiable(_addons);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sourcesJson = await _secure.read(key: _sourcesKey);
      if (sourcesJson != null && sourcesJson.isNotEmpty) {
        final decoded = jsonDecode(sourcesJson);
        if (decoded is List) {
          _addons.clear();
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _addons.add(AddonEntry.fromJson(item));
            } else if (item is Map) {
              _addons.add(AddonEntry.fromJson(item.cast<String, dynamic>()));
            }
          }
        }
      } else {
        // Legacy single-addon migration
        final legacyUrl = await _secure.read(key: _urlKey);
        if (legacyUrl != null && legacyUrl.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final enabled = prefs.getBool(_enabledKey) ?? true;
          final quality = AddonQuality.fromWire(prefs.getString(_qualityKey));
          final name = prefs.getString(_nameKey) ?? 'Addon';
          _addons.add(AddonEntry(
            id: 'legacy',
            name: name,
            baseUrl: legacyUrl,
            enabled: enabled,
            quality: quality,
          ));
          await _save();
        }
      }
    } catch (e) {
      debugPrint('AddonService: load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final jsonList = jsonEncode([for (final a in _addons) a.toJson()]);
      await _secure.write(key: _sourcesKey, value: jsonList);
      final prefs = await SharedPreferences.getInstance();
      if (_addons.isNotEmpty) {
        final first = _addons.first;
        await _secure.write(key: _urlKey, value: first.baseUrl);
        await prefs.setString(_nameKey, first.name);
        await prefs.setBool(_enabledKey, isEnabled);
        await prefs.setString(_qualityKey, first.quality.wire);
      } else {
        await _secure.delete(key: _urlKey);
        await prefs.remove(_nameKey);
        await prefs.setBool(_enabledKey, false);
      }
    } catch (e) {
      debugPrint('AddonService: save failed: $e');
    }
  }

  /// Checks the URL serves a playable addon manifest, then adds it.
  /// If the addon is already installed, refreshes its manifest and keeps its position.
  /// Throws [AddonException] with a message fit to show the user.
  Future<AddonManifest> install(String rawUrl) async {
    if (!AddonClient.looksValid(rawUrl)) {
      throw const AddonException('That doesn\'t look like an addon URL');
    }
    final client = AddonClient(rawUrl);
    AddonManifest manifest;
    try {
      manifest = await client.manifest();
    } catch (manifestError) {
      // Manifest probe fallback: if /manifest.json isn't served or fails,
      // probe whether /search answers (BitChord accepts addons with no manifest).
      final canSearch = await client.probeSearch();
      if (canSearch) {
        manifest = AddonManifest(
          id: Uri.tryParse(client.baseUrl)?.host ?? 'addon',
          name: Uri.tryParse(client.baseUrl)?.host ?? 'Addon',
          version: '1.0.0',
          resources: const ['search', 'stream'],
        );
      } else {
        client.close();
        if (manifestError is AddonException) rethrow;
        if (manifestError is TimeoutException) {
          throw const AddonException('The addon didn\'t answer in time');
        }
        throw AddonException('Couldn\'t reach the addon ($manifestError)');
      }
    }
    if (!manifest.isPlayable) {
      client.close();
      throw const AddonException('This addon can\'t search and stream tracks');
    }

    final existingIndex =
        _addons.indexWhere((a) => a.baseUrl == client.baseUrl);
    if (existingIndex != -1) {
      _addons[existingIndex].close();
      _addons[existingIndex] = AddonEntry(
        id: _addons[existingIndex].id,
        name: manifest.displayName,
        baseUrl: client.baseUrl,
        enabled: true,
        quality: _addons[existingIndex].quality,
        client: client,
      );
    } else {
      _addons.add(AddonEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: manifest.displayName,
        baseUrl: client.baseUrl,
        enabled: true,
        quality: AddonQuality.lossless,
        client: client,
      ));
    }

    _clearCache();
    await _save();
    notifyListeners();
    return manifest;
  }

  /// Removes an addon at [index].
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _addons.length) return;
    final removed = _addons.removeAt(index);
    removed.close();
    _clearCache();
    await _save();
    notifyListeners();
  }

  /// Removes an addon by [id].
  Future<void> removeAddon(String id) async {
    final idx = _addons.indexWhere((a) => a.id == id);
    if (idx != -1) {
      await removeAt(idx);
    }
  }

  /// Removes all installed addons.
  Future<void> remove() async {
    for (final a in _addons) {
      a.close();
    }
    _addons.clear();
    _clearCache();
    await _save();
    notifyListeners();
  }

  /// Reorders an addon from [oldIndex] to [newIndex] to change priority.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _addons.length) return;
    if (newIndex < 0 || newIndex >= _addons.length) return;
    if (oldIndex == newIndex) return;
    final item = _addons.removeAt(oldIndex);
    _addons.insert(newIndex, item);
    _clearCache();
    await _save();
    notifyListeners();
  }

  /// Sets whether all addons are enabled.
  Future<void> setEnabled(bool enabled) async {
    for (final a in _addons) {
      a.enabled = enabled;
    }
    await _save();
    notifyListeners();
  }

  /// Sets whether a specific addon is enabled.
  Future<void> setAddonEnabled(int index, bool enabled) async {
    if (index < 0 || index >= _addons.length) return;
    _addons[index].enabled = enabled;
    await _save();
    notifyListeners();
  }

  /// Sets the preferred quality tier for the primary addon.
  Future<void> setQuality(AddonQuality quality) async {
    if (_addons.isEmpty) return;
    if (_addons.first.quality == quality) return;
    _addons.first.quality = quality;
    _clearCache();
    await _save();
    notifyListeners();
  }

  /// Sets the preferred quality tier for a specific addon.
  Future<void> setAddonQuality(int index, AddonQuality quality) async {
    if (index < 0 || index >= _addons.length) return;
    if (_addons[index].quality == quality) return;
    _addons[index].quality = quality;
    _clearCache();
    await _save();
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting({List<AddonEntry>? addons, bool? atmosSupported}) {
    _testAtmosSupport = atmosSupported;
    _allowAtmos = false;
    _failedAtmos.clear();
    _clearCache();
    for (final a in _addons) {
      a.close();
    }
    _addons.clear();
    if (addons != null) {
      _addons.addAll(addons);
    }
    _loaded = true;
  }

  void _clearCache() {
    _cacheRevision++;
    _cache.clear();
    _resolvedAt.clear();
  }

  final _matchesController =
      StreamController<({String trackId, AddonMatch match})>.broadcast();

  /// Every lossless copy as it's found, whoever asked. The player listens,
  /// so the song playing moves onto its copy the moment one turns up.
  Stream<({String trackId, AddonMatch match})> get matches =>
      _matchesController.stream;

  /// Whether the addon has answered that it has no lossless copy of [track]
  /// — as opposed to not having been reachable to ask.
  bool isSettledMiss(Track track) =>
      _cache.containsKey(track.id) && _cache[track.id] == null;

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

  /// The preferred Atmos or lossless copy of [track], or null when no addon has one (or
  /// none are installed, enabled or reachable). Never throws.
  Future<AddonMatch?> matchFor(Track track) async {
    if (!isEnabled) return null;
    if (track.localFilePath != null || track.id.startsWith('local_')) {
      return null;
    }
    final preferAtmos = await canPlayAtmos(track);
    final revision = _cacheRevision;
    final key = '${track.id}:$revision:$preferAtmos';
    if (_cache.containsKey(track.id)) {
      if (_cache[track.id] == null) return null;
      final fresh = cachedFor(track);
      if (fresh != null) return fresh;
    }
    return _inFlight[key] ??=
        _resolve(
              track,
              knownMatch: _cache[track.id],
              preferAtmos: preferAtmos,
              revision: revision,
            )
            .then((match) {
              if (revision != _cacheRevision) return null;
              if (match?.stream.isAtmos == true &&
                  _failedAtmos.contains(track.id)) {
                return null;
              }
              return match;
            })
            .whenComplete(() {
              _inFlight.remove(key);
            });
  }

  /// The lossless copy of [track] to download, or null when no addon has one
  /// (or none could be reached). Never throws.
  ///
  /// Asks for a download rather than a stream, and keeps the answer to
  /// itself: its URL isn't one to hand the player, and nothing here should
  /// move the song playing onto FLAC. What's already known about the track
  /// is still used, so a settled miss or a known copy costs no new search.
  Future<AddonMatch?> matchForDownload(Track track) async {
    await load();
    if (!isEnabled || track.id.startsWith('local_')) return null;
    final known = _cache[track.id];
    if (!_allowAtmos && known == null && isSettledMiss(track)) return null;
    return _resolve(
      track,
      knownMatch: known?.stream.isAtmos == true ? null : known,
      download: true,
    );
  }

  Future<AddonMatch?> _resolve(
    Track track, {
    AddonMatch? knownMatch,
    bool download = false,
    bool preferAtmos = false,
    int? revision,
  }) async {
    bool acceptable(AddonStream stream, bool atmos) =>
        stream.isLossless || (atmos && stream.isPlayableAtmos);
    AddonMatch makeMatch(
      AddonEntry entry,
      AddonTrack candidate,
      AddonStream stream,
    ) => AddonMatch(
        addonName: entry.name,
        addonId: entry.id,
        track: candidate,
        stream: stream,
      );

    void announce(AddonMatch match) {
      if (download || revision != _cacheRevision) return;
      if (match.stream.isAtmos && _failedAtmos.contains(track.id)) return;
      _remember(track.id, match);
      _matchesController.add((trackId: track.id, match: match));
    }

    final active = _addons.where((a) => a.enabled).toList();
    if (knownMatch != null) {
      final entry = active
          .where(
            (a) => a.id == knownMatch.addonId || a.name == knownMatch.addonName,
          )
          .firstOrNull;
      if (entry != null) {
        try {
          final stream = await entry.client.stream(
            knownMatch.track.id,
            quality: entry.quality,
            download: download,
            preferAtmos: preferAtmos,
            atmosTrack: knownMatch.track.isAtmos,
          );
          if (acceptable(stream, preferAtmos && !download)) {
            final match = makeMatch(entry, knownMatch.track, stream);
            announce(match);
            return match;
          }
        } catch (_) {
          // An expired or unavailable stream needs a new search.
        }
      }
    }
    var settled = false;
    for (final entry in active) {
      // Try Atmos then stereo from the same source before moving down priority.
      for (final atmos in [if (preferAtmos && !download) true, false]) {
        if (!download && revision != _cacheRevision) return null;
        try {
          final candidate = await _findCandidate(
            entry.client,
            track,
            entry.quality,
            preferAtmos: atmos,
          );
          if (candidate == null) {
            settled = true;
            continue;
          }
          final stream = await entry.client.stream(
            candidate.id,
            quality: entry.quality,
            download: download,
            preferAtmos: atmos,
            atmosTrack: candidate.isAtmos,
          );
          if (!acceptable(stream, atmos)) {
            settled = true;
            continue;
          }
          final match = makeMatch(entry, candidate, stream);
          announce(match);
          return match;
        } on AddonMiss catch (error) {
          debugPrint(
            '[Lossless] [${entry.name}] Miss for "${track.title}": $error',
          );
          settled = true;
        } catch (error) {
          debugPrint(
            '[Lossless] [${entry.name}] Error for "${track.title}": $error',
          );
        }
      }
    }
    if (settled && !download && revision == _cacheRevision) {
      _remember(track.id, null);
    }
    return null;
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
    AddonQuality quality, {
    bool preferAtmos = false,
  }) async {
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
      preferAtmos: preferAtmos,
    );
    // A dubbed release usually differs from the original only by the
    // language on its album, so ask for that language by name first; the
    // plain search can rank the other languages' copies above it.
    final languages = languageTags('${track.title} ${track.album ?? ''}');
    if (languages.isNotEmpty) {
      final tagged = await client.search(
        '$primaryArtist $title ${languages.first}',
        quality: quality,
        preferAtmos: preferAtmos,
      );
      final hit = pick(tagged);
      if (hit != null) return hit;
    }
    final results = await client.search(
      '$primaryArtist $title',
      quality: quality,
      preferAtmos: preferAtmos,
    );
    final hit = pick(results);
    if (hit == null && results.isNotEmpty) {
      debugPrint(
        '[Lossless] None of ${results.length} results matched "${track.title}" '
        'by ${track.artist}; top: ${results.take(3).map((r) => '"${r.title}" / ${r.artist} / ${r.album} / ${r.duration.inSeconds}s${r.isLossless ? '' : ' (lossy)'}').join('; ')}',
      );
    }
    return hit;
  }

  /// The search hit that is the same recording as what's playing, or null.
  ///
  /// A different recording is worse than no upgrade — swapping a live take,
  /// a remix or another language's dub in mid-song is jarring — so the bar
  /// is: same title once normalised, the same take markers ("Remix",
  /// "Live"…) and the same language, every artist credited, a duration
  /// within a few seconds when both are known. Atmos is a separate mix and
  /// is only preferred when the playback backend supports it.
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
    bool preferAtmos = false,
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
      if (hit.isAtmos ? !preferAtmos : !hit.isLossless) continue;
      if (CanvasArtwork.normalizeForMatch(hit.title) != wantTitle) continue;
      if (!setEquals(_effectiveTakes(hit, wantTakes), wantTakes)) continue;
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
      var score = 10 + (preferAtmos && hit.isAtmos ? 100 : 0);
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
      // Not a veto (the release name may just be packaging), but between
      // otherwise equal rows, one whose album names a take nobody asked for
      // is the less likely copy.
      if (takeMarkers(hit.album).any((t) => !wantTakes.contains(t))) score -= 3;
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

  /// The no-vocal takes: a row from an "Instrumental" release *is* the
  /// instrumental even when its own title says nothing.
  static const _noVocalTakes = {'instrumental', 'karaoke', 'acapella'};

  /// A hit's take markers, completed from its album the way BitChord's
  /// matcher does. Catalogues often keep the take on the release rather than
  /// the row (Tidal's "KALYANI" on the album "KALYANI (Remix)"), so a marker
  /// the request asked for counts when the album carries it. No-vocal takes
  /// count from the album both ways. Anything else on an album ("Remixes",
  /// "Live at…") describes the release and is ignored.
  static Set<String> _effectiveTakes(AddonTrack hit, Set<String> wanted) {
    final album = takeMarkers(hit.album);
    return {
      ...takeMarkers(hit.title),
      ...album.where((t) => wanted.contains(t) || _noVocalTakes.contains(t)),
    };
  }

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
