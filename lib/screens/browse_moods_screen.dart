import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';

/// Mood category model
class MoodCategory {
  final String title;
  final List<MoodItem> items;

  const MoodCategory({required this.title, required this.items});
}

/// Mood item model
class MoodItem {
  final String title;
  final String? browseId;
  final String? params;

  const MoodItem({required this.title, this.browseId, this.params});
}

/// Predefined moods and genres (static list since API may not be available)
final List<MoodCategory> _defaultMoods = [
  MoodCategory(
    title: 'Moods',
    items: [
      MoodItem(title: 'Chill', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Party', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Workout', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Focus', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Sleep', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Happy', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Sad', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Romance', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(
        title: 'Feel Good',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        title: 'Energize',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
  MoodCategory(
    title: 'Genres',
    items: [
      MoodItem(title: 'Pop', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Rock', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Hip-Hop', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'R&B', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(
        title: 'Electronic',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(title: 'Dance', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Jazz', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(
        title: 'Classical',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(title: 'Country', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Metal', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Indie', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'K-Pop', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Latin', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(
        title: 'Bollywood',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
  MoodCategory(
    title: 'Activities',
    items: [
      MoodItem(title: 'Driving', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Cooking', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(title: 'Gaming', browseId: 'FEmusic_moods_and_genres_category'),
      MoodItem(
        title: 'Studying',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        title: 'Meditation',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
];

/// Browse moods and genres screen
class BrowseMoodsScreen extends ConsumerWidget {
  const BrowseMoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: const Text('Moods & Genres'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _defaultMoods.length,
        itemBuilder: (context, index) {
          final category = _defaultMoods[index];
          return _buildCategorySection(
            context,
            ref,
            category,
            isDark,
            colorScheme,
          );
        },
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    WidgetRef ref,
    MoodCategory category,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            category.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: category.items
              .map(
                (item) =>
                    _buildMoodChip(context, ref, item, isDark, colorScheme),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMoodChip(
    BuildContext context,
    WidgetRef ref,
    MoodItem item,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final color = _getMoodColor(item.title);

    return InkWell(
      onTap: () => _searchMood(context, ref, item),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.8), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          item.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _searchMood(BuildContext context, WidgetRef ref, MoodItem item) async {
    // Navigate to search results for this mood/genre
    // Uses the existing search functionality
    final innerTube = ref.read(innerTubeServiceProvider);

    try {
      // Search for playlists matching this mood
      final results = await innerTube.search(
        '${item.title} playlist',
        filter: 'playlists',
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                MoodPlaylistsScreen(mood: item, playlists: results.playlists),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Color _getMoodColor(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('chill') || lowerTitle.contains('relax'))
      return Colors.blue;
    if (lowerTitle.contains('party') || lowerTitle.contains('dance'))
      return Colors.pink;
    if (lowerTitle.contains('workout') || lowerTitle.contains('energy'))
      return Colors.orange;
    if (lowerTitle.contains('focus') || lowerTitle.contains('study'))
      return Colors.purple;
    if (lowerTitle.contains('sleep') || lowerTitle.contains('meditation'))
      return Colors.indigo;
    if (lowerTitle.contains('happy') || lowerTitle.contains('feel good'))
      return Colors.amber.shade700;
    if (lowerTitle.contains('sad') || lowerTitle.contains('melanchol'))
      return Colors.blueGrey;
    if (lowerTitle.contains('romance') || lowerTitle.contains('love'))
      return Colors.red;
    if (lowerTitle.contains('rock') || lowerTitle.contains('metal'))
      return Colors.grey.shade800;
    if (lowerTitle.contains('hip') || lowerTitle.contains('rap'))
      return Colors.amber.shade800;
    if (lowerTitle.contains('pop')) return Colors.teal;
    if (lowerTitle.contains('jazz') || lowerTitle.contains('blues'))
      return Colors.brown;
    if (lowerTitle.contains('country')) return Colors.green.shade700;
    if (lowerTitle.contains('classical')) return Colors.deepPurple;
    if (lowerTitle.contains('electronic') || lowerTitle.contains('edm'))
      return Colors.cyan;
    if (lowerTitle.contains('indie')) return Colors.lime.shade700;
    if (lowerTitle.contains('k-pop')) return Colors.pink.shade300;
    if (lowerTitle.contains('latin')) return Colors.red.shade400;
    if (lowerTitle.contains('bollywood')) return Colors.orange.shade700;
    if (lowerTitle.contains('r&b')) return Colors.deepOrange;
    if (lowerTitle.contains('driv')) return Colors.blueGrey.shade700;
    if (lowerTitle.contains('cook')) return Colors.orange.shade600;
    if (lowerTitle.contains('gam')) return Colors.green.shade600;

    // Generate consistent color from title hash
    final hash = title.hashCode.abs();
    return Color.fromARGB(
      255,
      100 + (hash % 100),
      100 + ((hash >> 8) % 100),
      100 + ((hash >> 16) % 100),
    );
  }
}

/// Screen to display playlists for a specific mood
class MoodPlaylistsScreen extends ConsumerWidget {
  final MoodItem mood;
  final List<Playlist> playlists;

  const MoodPlaylistsScreen({
    super.key,
    required this.mood,
    required this.playlists,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerService = ref.watch(audioPlayerServiceProvider);

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: Text(mood.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: playlists.isEmpty
          ? Center(
              child: Text(
                'No playlists found',
                style: TextStyle(
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _buildPlaylistCard(
                  context,
                  playlist,
                  isDark,
                  playerService,
                );
              },
            ),
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    Playlist playlist,
    bool isDark,
    dynamic playerService,
  ) {
    return GestureDetector(
      onTap: () {
        // Navigate to playlist screen
        Navigator.pushNamed(context, '/playlist', arguments: playlist.id);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: playlist.thumbnailUrl != null
                    ? Image.network(playlist.thumbnailUrl!, fit: BoxFit.cover)
                    : Container(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                        child: const Icon(Iconsax.music_playlist, size: 48),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                playlist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
