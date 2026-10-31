import 'dart:ui' as ui;

enum CanvasSource { tidal, community, appleMusic }

/// A looping video that stands in for a track's cover art — Tidal Video Cover,
/// Apple Music Motion Artwork, or Community Canvas.
class CanvasArtwork {
  final String url;
  final String? fallbackUrl;
  final String? title;
  final String? artist;
  final String? album;
  final CanvasSource source;

  const CanvasArtwork({
    required this.url,
    this.fallbackUrl,
    this.title,
    this.artist,
    this.album,
    required this.source,
  });

  /// Whether this clip accurately belongs to the track or album requested.
  /// Fold away punctuation, casing, bracketed noise, and accented characters.
  ///
  /// Strict on purpose: every source happily answers a search with another
  /// song by the same artist, and a wrong clip is worse than none (the still
  /// cover is always underneath). So the title must be the same once
  /// normalised, every artist asked for must be credited, and when both
  /// sides name an album it must be the same album.
  bool matches(String wantTitle, String wantArtist, [String? wantAlbum]) {
    final normWantTitle = normalizeForMatch(wantTitle);
    final titleOk =
        title == null ||
        normWantTitle.isEmpty ||
        normalizeForMatch(title!) == normWantTitle;

    final artistOk =
        artist == null ||
        wantArtist.trim().isEmpty ||
        allCredited(wantArtist, splitArtists(artist!));

    final ourAlbum = album == null ? '' : _albumKey(album!);
    final normWantAlbum = wantAlbum == null ? '' : _albumKey(wantAlbum);
    final albumOk =
        ourAlbum.isEmpty || normWantAlbum.isEmpty || ourAlbum == normWantAlbum;

    return titleOk && artistOk && albumOk;
  }

  /// Two-letter store region for the catalogue lookups. Motion artwork is
  /// licensed per storefront, so the device's own region finds what the
  /// listener can actually see; "us" when the locale has no usable country.
  static final String storefront = () {
    final country = ui.PlatformDispatcher.instance.locale.countryCode;
    return country != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(country)
        ? country.toLowerCase()
        : 'us';
  }();

  /// Whether every artist in [wantArtist] appears among [credited]
  /// (already normalised), compared whole rather than by substring.
  /// Apple names singles and EPs "Name - Single" / "Name - EP"; YouTube
  /// Music doesn't, so those suffixes come off before albums are compared.
  static String _albumKey(String raw) => normalizeForMatch(
    raw.replaceFirst(
      RegExp(r'\s+-\s+(?:single|ep)\s*$', caseSensitive: false),
      '',
    ),
  );

  static bool allCredited(String wantArtist, List<String> credited) {
    final wanted = splitArtists(wantArtist);
    if (wanted.isEmpty || credited.isEmpty) return false;
    return wanted.every(credited.contains);
  }

  static String foldDiacritics(String text) {
    const withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖØòóôõöøÈÉÊËèéêëÌÍÎÏìíîïÙÚÛÜùúûüÝýÿÑñÇç';
    const noDia = 'AAAAAAaaaaaaOOOOOOooooooEEEEeeeeIIIIiiiiUUUUuuuuYyyNnCc';
    var out = text;
    for (int i = 0; i < withDia.length; i++) {
      out = out.replaceAll(withDia[i], noDia[i]);
    }
    return out;
  }

  static String normalizeForMatch(String raw) {
    return foldDiacritics(raw)
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> splitArtists(String raw) {
    return raw
        .split(
          RegExp(
            r'(?:\s*,\s*|\s*&\s*|\s+×\s+|\s+x\s+|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)',
            caseSensitive: false,
          ),
        )
        .map(normalizeForMatch)
        .where((element) => element.isNotEmpty)
        .toList();
  }
}
