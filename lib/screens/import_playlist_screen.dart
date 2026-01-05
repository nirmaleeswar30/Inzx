import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';

/// Screen to import playlists from YouTube Music
class ImportPlaylistScreen extends ConsumerStatefulWidget {
  const ImportPlaylistScreen({super.key});

  @override
  ConsumerState<ImportPlaylistScreen> createState() =>
      _ImportPlaylistScreenState();
}

class _ImportPlaylistScreenState extends ConsumerState<ImportPlaylistScreen> {
  List<Playlist> _ytmPlaylists = [];
  bool _isLoading = true;
  String? _error;
  Set<String> _importing = {};
  Set<String> _imported = {};

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final innerTube = ref.read(innerTubeServiceProvider);
      final playlists = await innerTube.getSavedPlaylists();
      setState(() {
        _ytmPlaylists = playlists;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _importPlaylist(Playlist playlist) async {
    if (_importing.contains(playlist.id)) return;

    setState(() => _importing.add(playlist.id));

    try {
      final innerTube = ref.read(innerTubeServiceProvider);

      // Fetch full playlist with tracks
      final fullPlaylist = await innerTube.getPlaylist(playlist.id);

      // Create local playlist with same name
      final localPlaylistsNotifier = ref.read(localPlaylistsProvider.notifier);

      // Create playlist
      localPlaylistsNotifier.createPlaylist(
        '${playlist.title} (Imported)',
        description: 'Imported from YouTube Music',
      );

      // Get the newly created playlist
      final localPlaylists = ref.read(localPlaylistsProvider);
      final newPlaylist = localPlaylists.lastOrNull;

      if (newPlaylist != null && fullPlaylist?.tracks != null) {
        // Add all tracks
        for (final track in fullPlaylist!.tracks!) {
          localPlaylistsNotifier.addTrackToPlaylist(newPlaylist.id, track);
        }
      }

      setState(() {
        _importing.remove(playlist.id);
        _imported.add(playlist.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported "${playlist.title}"')));
      }
    } catch (e) {
      setState(() => _importing.remove(playlist.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      appBar: AppBar(
        title: const Text('Import from YouTube Music'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(isDark)
          : _ytmPlaylists.isEmpty
          ? _buildEmpty(isDark)
          : _buildPlaylistList(isDark, colorScheme),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Iconsax.warning_2, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            'Failed to load playlists',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure you\'re logged in to YouTube Music',
            style: TextStyle(
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadPlaylists,
            icon: const Icon(Iconsax.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Iconsax.music_playlist,
            size: 64,
            color: isDark ? Colors.white38 : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'No playlists found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create some playlists in YouTube Music first',
            style: TextStyle(
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistList(bool isDark, ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _ytmPlaylists.length,
      itemBuilder: (context, index) {
        final playlist = _ytmPlaylists[index];
        final isImporting = _importing.contains(playlist.id);
        final isImported = _imported.contains(playlist.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: playlist.thumbnailUrl != null
                    ? Image.network(playlist.thumbnailUrl!, fit: BoxFit.cover)
                    : Container(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                        child: const Icon(Iconsax.music_playlist),
                      ),
              ),
            ),
            title: Text(
              playlist.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${playlist.trackCount ?? 0} tracks',
              style: TextStyle(
                color: isDark ? Colors.white54 : MineColors.textSecondary,
              ),
            ),
            trailing: isImported
                ? const Icon(Iconsax.tick_circle, color: Colors.green)
                : isImporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: Icon(Iconsax.import_1, color: colorScheme.primary),
                    onPressed: () => _importPlaylist(playlist),
                  ),
          ),
        );
      },
    );
  }
}

/// Album radio mode extension
/// Adds ability to start radio from an album
extension AlbumRadioExtension on Album {
  /// Start radio based on this album
  Future<void> startAlbumRadio(WidgetRef ref) async {
    final playerService = ref.read(audioPlayerServiceProvider);
    final innerTube = ref.read(innerTubeServiceProvider);

    try {
      // Get first track from album
      final albumDetails = await innerTube.getAlbum(id);
      final tracks = albumDetails?.tracks;

      if (tracks != null && tracks.isNotEmpty) {
        // Play first track with radio mode enabled
        await playerService.playTrack(tracks.first, enableRadio: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting album radio: $e');
      }
    }
  }
}

/// Artist radio mode extension
extension ArtistRadioExtension on Artist {
  /// Start radio based on this artist
  Future<void> startArtistRadio(WidgetRef ref) async {
    final playerService = ref.read(audioPlayerServiceProvider);
    final innerTube = ref.read(innerTubeServiceProvider);

    try {
      // Get top tracks from artist
      final artistDetails = await innerTube.getArtist(id);
      final topTracks = artistDetails?.topTracks;

      if (topTracks != null && topTracks.isNotEmpty) {
        // Play first track with radio mode enabled
        await playerService.playTrack(topTracks.first, enableRadio: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting artist radio: $e');
      }
    }
  }
}
