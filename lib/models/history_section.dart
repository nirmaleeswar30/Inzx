import 'track.dart';

/// Represents a section of listening history (e.g., 'Today', 'Yesterday')
class HistorySection {
  final String title;
  final List<Track> tracks;

  const HistorySection({
    required this.title,
    required this.tracks,
  });

  bool get isEmpty => tracks.isEmpty;
  bool get isNotEmpty => tracks.isNotEmpty;
}
