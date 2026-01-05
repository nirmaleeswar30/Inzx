import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'artist_page_screen.dart';

/// Legacy Artist screen - now redirects to OuterTune-style ArtistPageScreen
///
/// This class is kept for backwards compatibility with existing callers.
/// All navigation and UI is handled by ArtistPageScreen.
class ArtistScreen extends ConsumerWidget {
  final String artistId;
  final String? artistName;
  final String? thumbnailUrl;

  const ArtistScreen({
    super.key,
    required this.artistId,
    this.artistName,
    this.thumbnailUrl,
  });

  /// Opens the artist page screen
  static void open(
    BuildContext context, {
    required String artistId,
    String? name,
    String? thumbnailUrl,
  }) {
    ArtistPageScreen.open(
      context,
      artistId: artistId,
      name: name,
      thumbnailUrl: thumbnailUrl,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ArtistPageScreen(
      artistId: artistId,
      artistName: artistName,
      thumbnailUrl: thumbnailUrl,
    );
  }
}
