import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';

/// Mood category model
class MoodCategory {
  final String key;
  final List<MoodItem> items;

  const MoodCategory({required this.key, required this.items});
}

/// Mood item model
class MoodItem {
  final String key;
  final String searchTerm;
  final String? browseId;
  final String? params;

  const MoodItem({
    required this.key,
    required this.searchTerm,
    this.browseId,
    this.params,
  });
}

/// Predefined moods and genres (static list since API may not be available)
final List<MoodCategory> _defaultMoods = [
  MoodCategory(
    key: 'moods',
    items: [
      MoodItem(
        key: 'chill',
        searchTerm: 'Chill',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'party',
        searchTerm: 'Party',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'workout',
        searchTerm: 'Workout',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'focus',
        searchTerm: 'Focus',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'sleep',
        searchTerm: 'Sleep',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'happy',
        searchTerm: 'Happy',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'sad',
        searchTerm: 'Sad',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'romance',
        searchTerm: 'Romance',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'feel_good',
        searchTerm: 'Feel Good',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'energize',
        searchTerm: 'Energize',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
  MoodCategory(
    key: 'genres',
    items: [
      MoodItem(
        key: 'pop',
        searchTerm: 'Pop',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'rock',
        searchTerm: 'Rock',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'hip_hop',
        searchTerm: 'Hip-Hop',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'rnb',
        searchTerm: 'R&B',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'electronic',
        searchTerm: 'Electronic',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'dance',
        searchTerm: 'Dance',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'jazz',
        searchTerm: 'Jazz',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'classical',
        searchTerm: 'Classical',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'country',
        searchTerm: 'Country',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'metal',
        searchTerm: 'Metal',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'indie',
        searchTerm: 'Indie',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'k_pop',
        searchTerm: 'K-Pop',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'latin',
        searchTerm: 'Latin',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'bollywood',
        searchTerm: 'Bollywood',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
  MoodCategory(
    key: 'activities',
    items: [
      MoodItem(
        key: 'driving',
        searchTerm: 'Driving',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'cooking',
        searchTerm: 'Cooking',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'gaming',
        searchTerm: 'Gaming',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'studying',
        searchTerm: 'Studying',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
      MoodItem(
        key: 'meditation',
        searchTerm: 'Meditation',
        browseId: 'FEmusic_moods_and_genres_category',
      ),
    ],
  ),
];

String _localizedMoodCategoryTitle(BuildContext context, String key) {
  final l10n = context.l10n;
  switch (key) {
    case 'moods':
      return l10n.moodCategoryMoods;
    case 'genres':
      return l10n.moodCategoryGenres;
    case 'activities':
      return l10n.moodCategoryActivities;
    default:
      return key;
  }
}

String _localizedMoodItemTitle(BuildContext context, String key) {
  final l10n = context.l10n;
  switch (key) {
    case 'chill':
      return l10n.moodChill;
    case 'party':
      return l10n.moodParty;
    case 'workout':
      return l10n.moodWorkout;
    case 'focus':
      return l10n.moodFocus;
    case 'sleep':
      return l10n.moodSleep;
    case 'happy':
      return l10n.moodHappy;
    case 'sad':
      return l10n.moodSad;
    case 'romance':
      return l10n.moodRomance;
    case 'feel_good':
      return l10n.moodFeelGood;
    case 'energize':
      return l10n.moodEnergize;
    case 'pop':
      return l10n.genrePop;
    case 'rock':
      return l10n.genreRock;
    case 'hip_hop':
      return l10n.genreHipHop;
    case 'rnb':
      return l10n.genreRnb;
    case 'electronic':
      return l10n.genreElectronic;
    case 'dance':
      return l10n.genreDance;
    case 'jazz':
      return l10n.genreJazz;
    case 'classical':
      return l10n.genreClassical;
    case 'country':
      return l10n.genreCountry;
    case 'metal':
      return l10n.genreMetal;
    case 'indie':
      return l10n.genreIndie;
    case 'k_pop':
      return l10n.genreKPop;
    case 'latin':
      return l10n.genreLatin;
    case 'bollywood':
      return l10n.genreBollywood;
    case 'driving':
      return l10n.activityDriving;
    case 'cooking':
      return l10n.activityCooking;
    case 'gaming':
      return l10n.activityGaming;
    case 'studying':
      return l10n.activityStudying;
    case 'meditation':
      return l10n.activityMeditation;
    default:
      return key;
  }
}

/// Browse moods and genres screen
class BrowseMoodsScreen extends ConsumerWidget {
  const BrowseMoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark
          ? InzxColors.darkBackground
          : InzxColors.background,
      appBar: AppBar(
        title: Text(context.l10n.browseMoodsGenresTitle),
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
            _localizedMoodCategoryTitle(context, category.key),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
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
    final color = _getMoodColor(item.key);

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
          _localizedMoodItemTitle(context, item.key),
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
        '${item.searchTerm} playlist',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithMessage('$e'))),
        );
      }
    }
  }

  Color _getMoodColor(String key) {
    switch (key) {
      case 'chill':
        return Colors.blue;
      case 'party':
      case 'dance':
        return Colors.pink;
      case 'workout':
      case 'energize':
        return Colors.orange;
      case 'focus':
      case 'studying':
        return Colors.purple;
      case 'sleep':
      case 'meditation':
        return Colors.indigo;
      case 'happy':
      case 'feel_good':
        return Colors.amber.shade700;
      case 'sad':
        return Colors.blueGrey;
      case 'romance':
        return Colors.red;
      case 'rock':
      case 'metal':
        return Colors.grey.shade800;
      case 'hip_hop':
        return Colors.amber.shade800;
      case 'pop':
        return Colors.teal;
      case 'jazz':
        return Colors.brown;
      case 'country':
        return Colors.green.shade700;
      case 'classical':
        return Colors.deepPurple;
      case 'electronic':
        return Colors.cyan;
      case 'indie':
        return Colors.lime.shade700;
      case 'k_pop':
        return Colors.pink.shade300;
      case 'latin':
        return Colors.red.shade400;
      case 'bollywood':
        return Colors.orange.shade700;
      case 'rnb':
        return Colors.deepOrange;
      case 'driving':
        return Colors.blueGrey.shade700;
      case 'cooking':
        return Colors.orange.shade600;
      case 'gaming':
        return Colors.green.shade600;
    }

    final hash = key.hashCode.abs();
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
          ? InzxColors.darkBackground
          : InzxColors.background,
      appBar: AppBar(
        title: Text(_localizedMoodItemTitle(context, mood.key)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: playlists.isEmpty
          ? Center(
              child: Text(
                context.l10n.noPlaylistsFound,
                style: TextStyle(
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
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
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
