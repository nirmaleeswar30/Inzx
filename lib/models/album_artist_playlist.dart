import 'package:equatable/equatable.dart';
import 'track.dart';

/// Represents a music album
/// Represents a music album
class Album extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String? thumbnailUrl;
  final String? highResThumbnailUrl;
  final String? description;
  final String? year;
  final int? trackCount;
  final List<Track>? tracks;
  final Duration? totalDuration;
  final bool isYTMusic;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.thumbnailUrl,
    this.highResThumbnailUrl,
    this.description,
    this.year,
    this.trackCount,
    this.tracks,
    this.totalDuration,
    this.isYTMusic = false,
  });

  /// Get the best available thumbnail
  String? get bestThumbnail => highResThumbnailUrl ?? thumbnailUrl;

  /// Copy with modifications
  Album copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? thumbnailUrl,
    String? highResThumbnailUrl,
    String? description,
    String? year,
    int? trackCount,
    List<Track>? tracks,
    Duration? totalDuration,
    bool? isYTMusic,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      highResThumbnailUrl: highResThumbnailUrl ?? this.highResThumbnailUrl,
      description: description ?? this.description,
      year: year ?? this.year,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
      totalDuration: totalDuration ?? this.totalDuration,
      isYTMusic: isYTMusic ?? this.isYTMusic,
    );
  }

  @override
  List<Object?> get props => [id];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'thumbnailUrl': thumbnailUrl,
      'highResThumbnailUrl': highResThumbnailUrl,
      'description': description,
      'year': year,
      'trackCount': trackCount,
      'totalDuration': totalDuration?.inMilliseconds,
      'isYTMusic': isYTMusic,
    };
  }

  /// Create from JSON
  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      artistId: json['artistId'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      highResThumbnailUrl: json['highResThumbnailUrl'] as String?,
      description: json['description'] as String?,
      year: json['year'] as String?,
      trackCount: json['trackCount'] as int?,
      totalDuration: json['totalDuration'] != null
          ? Duration(milliseconds: json['totalDuration'] as int)
          : null,
      isYTMusic: json['isYTMusic'] as bool? ?? false,
    );
  }
}

/// Represents a music artist
class Artist extends Equatable {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? description;
  final int? subscriberCount;
  final List<Track>? topTracks;
  final List<Album>? albums;
  final List<Album>? singles; // Singles & EPs
  final List<Album>? appearsOn; // Albums where artist appears on tracks
  final List<Playlist>? playlists; // Artist playlists / curated
  final List<Artist>? similarArtists; // Fans also like
  final String? songsBrowseId; // For "See all songs" navigation
  final String? songsParams; // Required params for artist songs browse
  final bool isSubscribed;

  const Artist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.description,
    this.subscriberCount,
    this.topTracks,
    this.albums,
    this.singles,
    this.appearsOn,
    this.playlists,
    this.similarArtists,
    this.songsBrowseId,
    this.songsParams,
    this.isSubscribed = false,
  });

  /// Formatted subscriber count
  String? get formattedSubscribers {
    if (subscriberCount == null) return null;
    if (subscriberCount! >= 1000000) {
      return '${(subscriberCount! / 1000000).toStringAsFixed(1)}M subscribers';
    } else if (subscriberCount! >= 1000) {
      return '${(subscriberCount! / 1000).toStringAsFixed(1)}K subscribers';
    }
    return '$subscriberCount subscribers';
  }

  /// Copy with modifications
  Artist copyWith({
    String? id,
    String? name,
    String? thumbnailUrl,
    String? description,
    int? subscriberCount,
    List<Track>? topTracks,
    List<Album>? albums,
    List<Album>? singles,
    List<Album>? appearsOn,
    List<Playlist>? playlists,
    List<Artist>? similarArtists,
    String? songsBrowseId,
    String? songsParams,
    bool? isSubscribed,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      description: description ?? this.description,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      topTracks: topTracks ?? this.topTracks,
      albums: albums ?? this.albums,
      singles: singles ?? this.singles,
      appearsOn: appearsOn ?? this.appearsOn,
      playlists: playlists ?? this.playlists,
      similarArtists: similarArtists ?? this.similarArtists,
      songsBrowseId: songsBrowseId ?? this.songsBrowseId,
      songsParams: songsParams ?? this.songsParams,
      isSubscribed: isSubscribed ?? this.isSubscribed,
    );
  }

  @override
  List<Object?> get props => [id];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'thumbnailUrl': thumbnailUrl,
      'description': description,
      'subscriberCount': subscriberCount,
      'isSubscribed': isSubscribed,
    };
  }

  /// Create from JSON
  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      description: json['description'] as String?,
      subscriberCount: json['subscriberCount'] as int?,
      isSubscribed: json['isSubscribed'] as bool? ?? false,
    );
  }
}

/// Represents a playlist
class Playlist extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? author;
  final int? trackCount;
  final List<Track>? tracks;
  final bool isLocal; // true if created by user locally
  final bool isYTMusic; // true if from YouTube Music
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Playlist({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.author,
    this.trackCount,
    this.tracks,
    this.isLocal = false,
    this.isYTMusic = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Copy with modifications
  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    String? thumbnailUrl,
    String? author,
    int? trackCount,
    List<Track>? tracks,
    bool? isLocal,
    bool? isYTMusic,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      author: author ?? this.author,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
      isLocal: isLocal ?? this.isLocal,
      isYTMusic: isYTMusic ?? this.isYTMusic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, isLocal, isYTMusic];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'author': author,
      'trackCount': trackCount,
      'tracks': tracks?.map((t) => t.toJson()).toList(),
      'isLocal': isLocal,
      'isYTMusic': isYTMusic,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  /// Create from JSON
  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      author: json['author'] as String?,
      trackCount: json['trackCount'] as int?,
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((t) => Track.fromJson(t as Map<String, dynamic>))
          .toList(),
      isLocal: json['isLocal'] as bool? ?? false,
      isYTMusic: json['isYTMusic'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }
}
