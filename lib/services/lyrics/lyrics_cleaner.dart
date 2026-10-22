/// Utility for cleaning and normalizing song titles and artist names for lyrics search.
class LyricsCleaner {
  /// Clean a song title by stripping metadata, movie references, video tags, etc.
  static String cleanTitle(String title) {
    if (title.isEmpty) return title;
    var cleaned = title;

    // 1. Remove bracketed / parenthetical additions like:
    // (From "Movie"), [From "Movie"], (Official Music Video), [Official Video],
    // (Audio), (Lyric Video), (Remastered 2021), (OST), (Live at...), (Visualizer)
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[][^\)\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 2. Remove "feat. X", "ft. X", "featuring X"
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(?:feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false),
      '',
    );

    // 3. Remove trailing video/audio indicators like:
    // " - Official Video", " - Lyric Video", " - Audio", " - HD", " - 4K", " - Full Song", " - Video Song"
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*-\s*(?:Official|Lyric|Music|Video|Audio|Visualizer|HD|4K|Remastered|Full Song|Video Song|Soundtrack|OST).*$',
        caseSensitive: false,
      ),
      '',
    );

    // 4. If title has " | " or " / " (e.g. "Pavala Mazhai | Kedi Billa Killadi Ranga | Yuvan"), extract the first segment
    if (cleaned.contains('|')) {
      cleaned = cleaned.split('|').first;
    }

    // 5. Remove leading/trailing quotes, dashes, punctuation, whitespace
    cleaned = cleaned
        .replaceAll(RegExp(r"""^[\s\-_"“”']+|[\s\-_"“”']+$"""), '')
        .trim();

    return cleaned.isNotEmpty ? cleaned : title.trim();
  }

  /// Clean artist name by removing topic suffixes, VEVO tags, and extracting the primary artist.
  static String cleanArtist(String artist) {
    if (artist.isEmpty) return artist;
    var cleaned = artist;

    // Remove "- Topic", "VEVO", "Official", etc.
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*-\s*Topic', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*VEVO', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*Official\s*(?:Channel)?', caseSensitive: false),
      '',
    );

    // Extract primary artist (before comma, &, x, feat)
    final primary = cleaned
        .split(
          RegExp(
            r'[,&/]|\b(?:feat\.?|ft\.?|featuring|x)\b',
            caseSensitive: false,
          ),
        )
        .first
        .trim();

    final result = primary.isNotEmpty ? primary : artist.trim();
    final lower = result.toLowerCase();
    const invalidArtists = {
      'song',
      'songs',
      'video',
      'videos',
      'track',
      'single',
      'unknown artist',
      'unknown',
    };
    if (invalidArtists.contains(lower)) {
      return '';
    }

    return result;
  }
}
