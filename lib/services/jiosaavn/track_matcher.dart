import 'dart:math';
import 'package:flutter/foundation.dart';

/// Target song being looked for across audio catalogues.
class TrackMatcherTarget {
  final String title;
  final String artist;

  /// Runtime in whole seconds; null when unknown.
  final int? durationSec;

  /// Release name, when known. Used to separate catalogue collisions.
  final String? album;

  /// Explicit/clean edition, null when unspecified.
  final bool? isExplicit;

  /// Music-video timing includes visual intros/outros that catalogue audio omits.
  final bool isVideo;

  const TrackMatcherTarget({
    required this.title,
    this.artist = '',
    this.durationSec,
    this.album,
    this.isExplicit,
    this.isVideo = false,
  });

  TrackMatcherTarget copyWith({
    String? title,
    String? artist,
    int? durationSec,
    String? album,
    bool? isExplicit,
    bool? isVideo,
  }) {
    return TrackMatcherTarget(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      durationSec: durationSec ?? this.durationSec,
      album: album ?? this.album,
      isExplicit: isExplicit ?? this.isExplicit,
      isVideo: isVideo ?? this.isVideo,
    );
  }

  @override
  String toString() =>
      'TrackMatcherTarget("$title", "$artist", duration: ${durationSec}s, album: "$album", explicit: $isExplicit, video: $isVideo)';
}

/// Common interface for any candidate song evaluated by [TrackMatcher].
abstract class TrackMatcherCandidate {
  String get title;
  String get artist;
  int? get durationSec;
  String? get album;
  bool? get isExplicit;
}

/// Simple model for testing or standalone candidate evaluation.
class MockCandidate implements TrackMatcherCandidate {
  @override
  final String title;
  @override
  final String artist;
  @override
  final int? durationSec;
  @override
  final String? album;
  @override
  final bool? isExplicit;

  const MockCandidate({
    required this.title,
    required this.artist,
    this.durationSec,
    this.album,
    this.isExplicit,
  });

  @override
  String toString() =>
      'MockCandidate("$title", "$artist", duration: ${durationSec}s, album: "$album", explicit: $isExplicit)';
}

/// A title split into the part that is the recording's identity and the
/// parts that are the catalogue listing's.
class TitleParts {
  /// The title proper, lowercased, one entry per word.
  final List<String> words;

  /// [words] with everything but letters and digits removed — what identity is compared on.
  final String core;

  /// Markers that mean a different take of the same song: `remix`, `live`, `acoustic`.
  final Set<String> versions;

  /// Words dropped with the packaging. A hint for scoring, never a veto.
  final Set<String> context;

  const TitleParts({
    required this.words,
    required this.core,
    required this.versions,
    required this.context,
  });

  @override
  String toString() =>
      'TitleParts(words: $words, core: "$core", versions: $versions, context: $context)';
}

/// Strict 6-layer [TrackMatcher] engine.
///
/// Decides whether one catalogue's track is genuinely the same recording
/// as another's, preventing wrong music, remixes, karaoke, loops, and covers
/// from being substituted under the right title.
class TrackMatcher {
  TrackMatcher._();

  // ── Weights ─────────────────────────────────────────────────────────────

  /// Everything that reaches scoring has already matched on title core and version markers.
  static const int baseScore = 100;
  static const int artistExact = 25;
  static const int artistShared = 10;

  /// Carried by a match the runtime vouched for rather than the credit. A
  /// penalty, not a pass: any candidate whose credit genuinely agrees beats
  /// it by at least 25, so this only ever decides what plays when nothing
  /// properly credited exists.
  static const int creditsDisagree = -30;

  /// How exactly two runtimes must agree before that is allowed to stand in
  /// for a shared credit (Indian soundtracks: composer vs singer credits).
  static const int creditOverrideSec = 2;
  static const int durationTight = 40;
  static const int durationLoose = 15;
  static const int albumExact = 35;
  static const int explicitExact = 20;
  static const int contextShared = 20;

  /// Within this many seconds is the same master, allowing for trimmed silence.
  static const int durationTightSec = 3;

  /// Past this, two tracks sharing a title are not sharing a recording.
  static const int durationLimitSec = 30;

  /// Visual intros/outros can make the video substantially longer than its audio master.
  static const int videoDurationLimitSec = 90;

  static const int bracketPasses = 3;
  static const int dashPasses = 3;

  static final RegExp bracketed = RegExp(r'[(\[]([^()\[\]]*)[)\]]');
  static final RegExp dash = RegExp(r'\s+[-–—|]+\s+');
  static final RegExp featuring = RegExp(r'\b(?:feat|ft|featuring|with)\b.*', caseSensitive: false);
  static final RegExp wordSplit = RegExp(r'[\s.·]+');
  static final RegExp nonAlnum = RegExp(r'[^a-z0-9]');
  static final RegExp artistSeparators = RegExp(
    r'\s*(?:[,&/;·|]|\band\b|\bx\b|\bvs\.?\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)\s*',
    caseSensitive: false,
  );

  /// What makes a listing a different recording rather than a different
  /// listing of the same one. A title carrying one of these on one side only
  /// is refused outright.
  static const Set<String> versionWords = {
    'remix', 'remixes', 'rmx', 'refix', 'flip', 'bootleg', 'mashup', 'medley',
    'live', 'concert', 'unplugged', 'acoustic', 'instrumental', 'karaoke',
    'vocals', 'vocal', 'acapella', 'acappella', 'backing', 'stems', 'stem',
    'cover', 'covers', 'demo', 'reprise', 'remake', 'rework', 'extended', 'edit',
    'version', 'mix', 'dub', 'vip', 'session', 'sessions',
    'sped', 'slowed', 'reverb', 'nightcore', 'lofi', 'orchestral', 'symphonic',
    'part', 'pt', 'chapter',
    'lullaby', 'lullabies', 'rendition', 'renditions', 'tribute', 'tributes',
    'parody', 'parodies',
  };

  /// Asides that read like a version and describe the ordinary release.
  static const Set<String> neutralSegments = {
    'albumversion', 'originalversion', 'originalmix', 'singleversion',
    'radioversion', 'radioedit', 'stereoversion', 'monoversion',
    'studioversion', 'fullversion', 'standardversion', 'explicitversion',
    'deluxeversion', 'originaltrack',
  };

  /// Packaging words, worth nothing as a tie-break because everything has them.
  static const Set<String> noiseWords = {
    'official', 'video', 'audio', 'lyrics', 'lyric', 'lyrical', 'visualizer',
    'song', 'songs', 'full', 'music', 'the', 'and', 'from', 'feat', 'ft',
    'featuring', 'with', 'new', 'latest', 'free', 'download', 'remaster',
    'remastered', 'explicit', 'clean', 'bonus', 'track', 'deluxe', 'original',
    'album', 'single', 'hd', 'hq', '4k', 'mp3',
  };

  static const Set<String> albumNoiseWords = {
    'album', 'deluxe', 'edition', 'expanded', 'remaster', 'remastered',
    'version', 'explicit', 'clean', 'bonus', 'anniversary',
  };

  /// Trailing labels an upload hangs on a title with no brackets to hold them.
  static const Set<String> trailingNoise = {
    'song', 'songs', 'video', 'audio', 'lyrics', 'lyric', 'lyrical',
    'official', 'full', 'hd', 'hq', '4k', 'mp3', 'ost', 'soundtrack',
  };

  /// Dropped from the core so that "Jack and Jill" and "Jack & Jill" are one title.
  static const Set<String> joiningWords = {'and'};

  // ── Asking ──────────────────────────────────────────────────────────────

  /// What to put to a source's search box, best query first.
  static List<String> queries(TrackMatcherTarget target) {
    final title = searchableTitle(target.title, artist: target.artist);
    if (title.trim().isEmpty) return const [];
    final artist = primaryArtist(target.artist);
    if (artist.trim().isEmpty) return [title];
    return ['$title $artist', title];
  }

  /// The title with packaging removed, version markers kept.
  static String searchableTitle(String title, {String artist = ''}) {
    final parts = parseTitle(title, artist: artist);
    return [...parts.words, ...parts.versions].join(' ');
  }

  /// The first credited artist — who a catalogue is most likely to file the track under.
  static String primaryArtist(String artist) {
    final parts = artist.toLowerCase().split(artistSeparators);
    return parts.isEmpty ? '' : parts.first.trim();
  }

  /// Whether both credits name at least one of the same artists.
  static bool sharesArtist(String wanted, String got) {
    final want = artistNames(wanted);
    final have = artistNames(got);
    return want.isNotEmpty &&
        have.isNotEmpty &&
        want.any((w) => have.any((h) => sameArtist(w, h)));
  }

  // ── Judging ─────────────────────────────────────────────────────────────

  /// The best of [candidates] that is genuinely [target], or null if none is.
  static T? best<T extends TrackMatcherCandidate>(
    List<T> candidates,
    TrackMatcherTarget target,
  ) =>
      ranked(candidates, target).firstOrNull;

  /// The catalogue counterpart for a music-video upload selected explicitly by the listener.
  static T? bestOfficialAudioForVideo<T extends TrackMatcherCandidate>(
    List<T> candidates,
    TrackMatcherTarget target,
  ) {
    final wanted = parseTitle(target.title, artist: target.artist);
    if (wanted.core.isEmpty) return null;

    final scored = <MapEntry<T, int>>[];
    for (final candidate in candidates) {
      final got = parseTitle(candidate.title, artist: candidate.artist);
      if (wanted.core != got.core || !setEquals(wanted.versions, got.versions)) {
        continue;
      }
      final artist = artistScore(target.artist, candidate.artist);
      if (artist == null) continue;

      int duration = 0;
      if (target.durationSec != null) {
        final actual = candidate.durationSec;
        duration = actual != null ? -(target.durationSec! - actual).abs() : -120;
      }
      scored.add(MapEntry(candidate, artist * 1000 + duration));
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  /// Every candidate that really is [target], most confident first.
  static List<T> ranked<T extends TrackMatcherCandidate>(
    List<T> candidates,
    TrackMatcherTarget target,
  ) {
    final scored = <MapEntry<T, int>>[];
    for (final candidate in candidates) {
      final s = score(candidate, target);
      if (s != null) {
        scored.add(MapEntry(candidate, s));
      }
    }

    final credited = scored
        .where((entry) => artistScore(target.artist, entry.key.artist) != null)
        .toList();

    final pool = credited.isNotEmpty ? credited : scored;
    pool.sort((a, b) => b.value.compareTo(a.value));
    return pool.map((e) => e.key).toList();
  }

  /// How confident this is the same recording, or null when it is not one.
  static int? score(TrackMatcherCandidate candidate, TrackMatcherTarget target) {
    final wanted = parseTitle(target.title, artist: target.artist);
    final got = parseTitle(candidate.title, artist: candidate.artist);
    if (wanted.core.isEmpty || got.core.isEmpty) return null;
    if (wanted.core != got.core) return null;
    if (!setEquals(wanted.versions, got.versions)) return null;

    final creditedArtist = artistScore(target.artist, candidate.artist);
    final duration = durationScore(
      target.durationSec,
      candidate.durationSec,
      allowVideoDrift: target.isVideo && creditedArtist != null,
    );
    if (duration == null) return null;

    final artist = creditedArtist ??
        (!target.isVideo && withinSeconds(candidate, target, creditOverrideSec)
            ? creditsDisagree
            : null);
    if (artist == null) return null;

    final explicit = explicitScore(target.isExplicit, candidate.isExplicit);
    if (explicit == null) return null;

    return baseScore +
        artist +
        duration +
        albumScore(target.album, candidate.album) +
        explicit +
        contextScore(wanted, got);
  }

  /// Whether otherwise valid rows describe more than one release while the
  /// requested track gives us no release with which to choose between them.
  static bool hasConflictingAlbums<T extends TrackMatcherCandidate>(
    List<T> candidates,
    TrackMatcherTarget target,
  ) {
    if (target.album != null && target.album!.trim().isNotEmpty) return false;
    final comparable = target.durationSec != null
        ? candidates.where((c) => withinSeconds(c, target, durationLimitSec)).toList()
        : candidates;
    if (target.durationSec != null && comparable.isEmpty) return false;
    final albumKeys = comparable
        .map((c) => albumKey(c.album))
        .whereType<String>()
        .toSet();
    return albumKeys.length > 1;
  }

  /// Resolves a catalogue release collision only when one candidate is plainly
  /// more specifically credited than every other close-duration candidate.
  static T? uniquelyMostCreditedCloseMatch<T extends TrackMatcherCandidate>(
    List<T> candidates,
    TrackMatcherTarget target,
  ) {
    final close = candidates
        .where((c) => withinSeconds(c, target, durationLimitSec))
        .toList();
    if (close.length < 2) return null;

    final ranked = close.map((c) => MapEntry(c, artistNames(c.artist).length)).toList();
    int topCredits = 0;
    for (final r in ranked) {
      if (r.value > topCredits) topCredits = r.value;
    }
    if (topCredits < 2) return null;

    final winners = ranked.where((r) => r.value == topCredits).map((r) => r.key).toList();
    return winners.length == 1 ? winners.first : null;
  }

  /// Whether [candidate] states a runtime, and one within [seconds] of [target]'s.
  static bool withinSeconds(
    TrackMatcherCandidate candidate,
    TrackMatcherTarget target,
    int seconds,
  ) {
    final wanted = target.durationSec;
    if (wanted == null) return false;
    final got = candidate.durationSec;
    if (got == null) return false;
    return (wanted - got).abs() <= seconds;
  }

  /// Helper for testing and simple binary match queries.
  static bool matches(
    TrackMatcherCandidate candidate,
    String title,
    String artist, [
    int? durationSec,
  ]) =>
      score(
        candidate,
        TrackMatcherTarget(
          title: title,
          artist: artist,
          durationSec: durationSec,
        ),
      ) !=
      null;

  // ── Title Parsing ─────────────────────────────────────────────────────────

  /// Splits a title into identity words, core alphanumeric string, versions, and context.
  static TitleParts parseTitle(String raw, {String artist = ''}) {
    final versions = <String>{};
    final context = <String>{};
    var text = raw.toLowerCase().replaceAll('&', ' and ');

    // 1. Bracketed asides, innermost first
    for (var i = 0; i < bracketPasses; i++) {
      if (!bracketed.hasMatch(text)) break;
      text = text.replaceAllMapped(bracketed, (match) {
        classify(match.group(1) ?? '', versions, context);
        return ' ';
      });
    }

    // 2. Unbalanced brackets
    final openParen = text.indexOf('(');
    final openBracket = text.indexOf('[');
    int open = -1;
    if (openParen >= 0 && openBracket >= 0) {
      open = min(openParen, openBracket);
    } else if (openParen >= 0) {
      open = openParen;
    } else if (openBracket >= 0) {
      open = openBracket;
    }
    if (open >= 0) {
      classify(text.substring(open), versions, context);
      text = text.substring(0, open);
    }

    // 3. Dash- and pipe-separated tails
    for (var i = 0; i < dashPasses; i++) {
      final dashMatch = dash.firstMatch(text);
      if (dashMatch == null) break;
      final head = text.substring(0, dashMatch.start);
      final tail = text.substring(dashMatch.end);
      if (isArtistName(head, artist)) {
        classify(head, versions, context);
        text = tail;
      } else {
        classify(tail, versions, context);
        text = head;
      }
    }

    // 4. Featuring tails
    text = text.replaceAll(featuring, ' ');

    // 5. Tokenize words
    var words = text
        .split(wordSplit)
        .map((w) => w.replaceAll(nonAlnum, ''))
        .where((w) => w.isNotEmpty && !joiningWords.contains(w))
        .toList();

    // 6. Strip trailing upload noise words
    while (words.length > 1 && trailingNoise.contains(words.last)) {
      words.removeLast();
    }

    return TitleParts(
      words: words,
      core: words.join(''),
      versions: versions,
      context: context,
    );
  }

  /// Files one dropped segment under [versions] or [context].
  static void classify(
    String segment,
    Set<String> versions,
    Set<String> context,
  ) {
    final words = segment
        .split(wordSplit)
        .map((w) => w.replaceAll(nonAlnum, ''))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return;
    if (neutralSegments.contains(words.join(''))) return;

    final marks = words.where((w) => versionWords.contains(w)).toList();
    if (marks.isNotEmpty) {
      versions.addAll(marks);
      return;
    }
    context.addAll(words.where((w) => w.length > 2 && !noiseWords.contains(w)));
  }

  /// Whether [text] is nothing but (part of) [artist] — the "Artist - Title" upload shape.
  static bool isArtistName(String text, String artist) {
    if (artist.trim().isEmpty) return false;
    final words = text
        .split(wordSplit)
        .map((w) => w.replaceAll(nonAlnum, ''))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;

    final credited = artist
        .toLowerCase()
        .split(wordSplit)
        .map((w) => w.replaceAll(nonAlnum, ''))
        .where((w) => w.isNotEmpty)
        .toSet();
    return words.every(credited.contains);
  }

  // ── Artist Matching ───────────────────────────────────────────────────────

  static int? artistScore(String wanted, String got) {
    final want = artistNames(wanted);
    final have = artistNames(got);
    if (want.isEmpty || have.isEmpty) return 0;
    final shared = sharesArtist(wanted, got);
    if (!shared) return null;
    return _artistSetEquals(want, have) ? artistExact : artistShared;
  }

  static Set<List<String>> artistNames(String value) {
    return value
        .toLowerCase()
        .split(artistSeparators)
        .map((name) {
          return name
              .split(wordSplit)
              .map((w) => w.replaceAll(nonAlnum, ''))
              .where((w) => w.length > 1)
              .toList();
        })
        .where((list) => list.isNotEmpty)
        .toSet();
  }

  static bool sameArtist(List<String> a, List<String> b) =>
      _runOf(a, b) || _runOf(b, a);

  static bool _runOf(List<String> outer, List<String> inner) {
    if (inner.isEmpty || inner.length > outer.length) return false;
    for (int at = 0; at <= outer.length - inner.length; at++) {
      bool match = true;
      for (int i = 0; i < inner.length; i++) {
        if (outer[at + i] != inner[i]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static bool _artistSetEquals(Set<List<String>> a, Set<List<String>> b) {
    if (a.length != b.length) return false;
    return a.every((listA) => b.any((listB) => listEquals(listA, listB)));
  }

  // ── Duration Matching ─────────────────────────────────────────────────────

  static int? durationScore(
    int? wanted,
    int? got, {
    bool allowVideoDrift = false,
  }) {
    if (wanted == null || got == null) return 0;
    final drift = (wanted - got).abs();
    if (drift > durationLimitSec &&
        allowVideoDrift &&
        drift <= videoDurationLimitSec) {
      return 0;
    }
    if (drift > durationLimitSec) return null;
    if (drift <= durationTightSec) return durationTight;
    return durationLoose;
  }

  // ── Album Matching ────────────────────────────────────────────────────────

  static int albumScore(String? wanted, String? got) {
    final want = albumKey(wanted);
    if (want == null) return 0;
    final have = albumKey(got);
    if (have == null) return 0;
    return want == have ? albumExact : 0;
  }

  static String? albumKey(String? value) {
    var text = (value ?? '').toLowerCase().trim();
    if (text.isEmpty) return null;
    for (var i = 0; i < bracketPasses; i++) {
      text = text.replaceAll(bracketed, ' ');
    }
    final words = text
        .split(wordSplit)
        .map((w) => w.replaceAll(nonAlnum, ''))
        .where((w) => w.isNotEmpty && !albumNoiseWords.contains(w))
        .toList();
    final key = words.join('');
    return key.isNotEmpty ? key : null;
  }

  // ── Explicit Flag Matching ────────────────────────────────────────────────

  static int? explicitScore(bool? wanted, bool? got) {
    if (wanted == null || got == null) return 0;
    if (wanted != got) return null;
    return explicitExact;
  }

  // ── Context Score ─────────────────────────────────────────────────────────

  static int contextScore(TitleParts wanted, TitleParts got) {
    return wanted.context.any(got.context.contains) ? contextShared : 0;
  }

  // ── Duration Parsing Helper ───────────────────────────────────────────────

  /// "3:45" or "1:02:03" as whole seconds; null for anything else.
  static int? secondsOf(String? text) {
    if (text == null) return null;
    final parts = text.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    int total = 0;
    for (final part in parts) {
      final num = int.tryParse(part.trim());
      if (num == null) return null;
      total = total * 60 + num;
    }
    return total > 0 ? total : null;
  }
}
