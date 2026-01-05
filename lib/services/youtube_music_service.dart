import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/models.dart' as models;

/// Service for fetching music data from YouTube Music
class YouTubeMusicService {
  static final YouTubeMusicService _instance = YouTubeMusicService._internal();
  factory YouTubeMusicService() => _instance;
  YouTubeMusicService._internal();

  final YoutubeExplode _yt = YoutubeExplode();

  /// Search for tracks (videos)
  Future<models.SearchResults> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) {
      return models.SearchResults.empty(query);
    }

    try {
      // Search returns VideoSearchList
      final searchList = await _yt.search.search(query);
      
      final tracks = <models.Track>[];

      for (final video in searchList.take(limit)) {
        tracks.add(_videoToTrack(video));
      }

      return models.SearchResults(
        query: query,
        tracks: tracks,
        albums: [],
        artists: [],
        playlists: [],
        hasMore: searchList.length >= limit,
      );
    } catch (e) {
      return models.SearchResults.empty(query);
    }
  }

  /// Search specifically for songs/tracks
  Future<List<models.Track>> searchTracks(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    try {
      final searchList = await _yt.search.search(query);
      
      return searchList
          .take(limit)
          .map(_videoToTrack)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get search suggestions
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final suggestions = await _yt.search.getQuerySuggestions(query);
      return suggestions.take(8).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get track details by video ID
  Future<models.Track?> getTrack(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return _videoToTrack(video);
    } catch (e) {
      return null;
    }
  }

  /// Get audio stream URL for playback
  Future<String?> getStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // Prefer audio-only streams for better performance and bandwidth
      final audioStreams = manifest.audioOnly;
      
      if (audioStreams.isNotEmpty) {
        // Get highest bitrate audio stream
        final bestAudio = audioStreams.withHighestBitrate();
        return bestAudio.url.toString();
      }
      
      // Fallback to muxed stream (audio + video, limited to 360p)
      final muxedStreams = manifest.muxed;
      if (muxedStreams.isNotEmpty) {
        final bestMuxed = muxedStreams.withHighestBitrate();
        return bestMuxed.url.toString();
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get audio stream info (for quality selection)
  Future<List<AudioOnlyStreamInfo>> getAudioStreams(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      return manifest.audioOnly.toList();
    } catch (e) {
      return [];
    }
  }

  /// Get playlist tracks
  Future<models.Playlist?> getPlaylist(String playlistId) async {
    try {
      final playlist = await _yt.playlists.get(playlistId);
      final videos = await _yt.playlists.getVideos(playlistId).toList();
      
      return models.Playlist(
        id: playlist.id.value,
        title: playlist.title,
        description: playlist.description,
        thumbnailUrl: playlist.thumbnails.highResUrl,
        author: playlist.author,
        trackCount: playlist.videoCount,
        tracks: videos.map(_videoToTrack).toList(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get channel/artist info
  Future<models.Artist?> getArtist(String channelId) async {
    try {
      final channel = await _yt.channels.get(channelId);
      final uploads = await _yt.channels.getUploads(channelId).take(10).toList();
      
      return models.Artist(
        id: channel.id.value,
        name: channel.title,
        thumbnailUrl: channel.logoUrl,
        subscriberCount: channel.subscribersCount,
        topTracks: uploads.map(_videoToTrack).toList(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get related/recommended tracks for a video
  Future<List<models.Track>> getRelatedTracks(String videoId, {int limit = 10}) async {
    try {
      // First get the video object
      final video = await _yt.videos.get(videoId);
      
      // Then get related videos using the Video object
      final relatedVideos = await _yt.videos.getRelatedVideos(video);
      
      if (relatedVideos == null) return [];
      
      return relatedVideos
          .take(limit)
          .map(_videoToTrack)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get trending/popular music
  Future<List<models.Track>> getTrendingMusic({int limit = 20}) async {
    try {
      // Search for popular music
      final results = await search('top hits 2024 music', limit: limit);
      return results.tracks;
    } catch (e) {
      return [];
    }
  }

  /// Convert Video to Track
  models.Track _videoToTrack(Video video) {
    return models.Track.fromYouTube(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      artistId: video.channelId.value,
      duration: video.duration ?? Duration.zero,
      thumbnailUrl: video.thumbnails.highResUrl,
    );
  }

  /// Dispose resources
  void dispose() {
    _yt.close();
  }
}
