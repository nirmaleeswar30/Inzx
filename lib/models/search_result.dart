import 'track.dart';
import 'album_artist_playlist.dart';

/// Represents different types of search results
enum SearchResultType { track, album, artist, playlist }

/// A single search result item
class SearchResultItem {
  final SearchResultType type;
  final Track? track;
  final Album? album;
  final Artist? artist;
  final Playlist? playlist;

  const SearchResultItem._({
    required this.type,
    this.track,
    this.album,
    this.artist,
    this.playlist,
  });

  factory SearchResultItem.track(Track track) {
    return SearchResultItem._(type: SearchResultType.track, track: track);
  }

  factory SearchResultItem.album(Album album) {
    return SearchResultItem._(type: SearchResultType.album, album: album);
  }

  factory SearchResultItem.artist(Artist artist) {
    return SearchResultItem._(type: SearchResultType.artist, artist: artist);
  }

  factory SearchResultItem.playlist(Playlist playlist) {
    return SearchResultItem._(
      type: SearchResultType.playlist,
      playlist: playlist,
    );
  }

  /// Get the title of this item
  String get title {
    switch (type) {
      case SearchResultType.track:
        return track!.title;
      case SearchResultType.album:
        return album!.title;
      case SearchResultType.artist:
        return artist!.name;
      case SearchResultType.playlist:
        return playlist!.title;
    }
  }

  /// Get the subtitle of this item
  String? get subtitle {
    switch (type) {
      case SearchResultType.track:
        return track!.artist;
      case SearchResultType.album:
        return album!.artist;
      case SearchResultType.artist:
        return artist!.formattedSubscribers;
      case SearchResultType.playlist:
        return playlist!.author;
    }
  }

  /// Get the thumbnail URL
  String? get thumbnailUrl {
    switch (type) {
      case SearchResultType.track:
        return track!.thumbnailUrl;
      case SearchResultType.album:
        return album!.thumbnailUrl;
      case SearchResultType.artist:
        return artist!.thumbnailUrl;
      case SearchResultType.playlist:
        return playlist!.thumbnailUrl;
    }
  }
}

/// Complete search results containing all types
class SearchResults {
  final String query;
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;
  final SearchResultItem? topResult; // YouTube's actual top result
  final bool hasMore;

  const SearchResults({
    required this.query,
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.topResult,
    this.hasMore = false,
  });

  /// Check if results are empty
  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  /// Get total result count
  int get totalCount =>
      tracks.length + albums.length + artists.length + playlists.length;

  /// Convert to a flat list of SearchResultItems
  List<SearchResultItem> toList() {
    return [
      ...tracks.map((t) => SearchResultItem.track(t)),
      ...albums.map((a) => SearchResultItem.album(a)),
      ...artists.map((a) => SearchResultItem.artist(a)),
      ...playlists.map((p) => SearchResultItem.playlist(p)),
    ];
  }

  /// Get top results (first few of each type)
  List<SearchResultItem> getTopResults({int maxPerType = 3}) {
    return [
      ...tracks.take(maxPerType).map((t) => SearchResultItem.track(t)),
      ...artists.take(maxPerType).map((a) => SearchResultItem.artist(a)),
      ...albums.take(maxPerType).map((a) => SearchResultItem.album(a)),
      ...playlists.take(maxPerType).map((p) => SearchResultItem.playlist(p)),
    ];
  }

  /// Create empty results
  factory SearchResults.empty(String query) {
    return SearchResults(query: query);
  }
}

/// Search suggestion
class SearchSuggestion {
  final String text;
  final bool isHistory; // true if from search history

  const SearchSuggestion({required this.text, this.isHistory = false});
}
