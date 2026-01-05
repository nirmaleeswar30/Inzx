import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/ytmusic_providers.dart';

/// Playlist picker sheet for adding tracks to playlists
class PlaylistPickerSheet extends ConsumerStatefulWidget {
  final Track track;

  const PlaylistPickerSheet({super.key, required this.track});

  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PlaylistPickerSheet(track: track),
    );
  }

  @override
  ConsumerState<PlaylistPickerSheet> createState() =>
      _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<PlaylistPickerSheet> {
  final _newPlaylistController = TextEditingController();
  bool _showCreateNew = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = textColor.withValues(alpha: 0.6);

    final playlistsAsync = ref.watch(ytMusicSavedPlaylistsProvider);
    final localPlaylists = ref.watch(localPlaylistsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add to Playlist',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: secondaryColor),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Create new playlist button
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Iconsax.add, color: colorScheme.primary),
            ),
            title: Text(
              'Create New Playlist',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
            onTap: () => setState(() => _showCreateNew = !_showCreateNew),
          ),

          // Create new playlist form
          if (_showCreateNew)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPlaylistController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Playlist name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      style: TextStyle(color: textColor),
                      onSubmitted: (_) => _createAndAdd(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _createAndAdd,
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Playlist list - combines YT Music playlists + local playlists
          Flexible(
            child: playlistsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.warning_2, size: 48, color: secondaryColor),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load playlists',
                      style: TextStyle(color: secondaryColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a local playlist instead',
                      style: TextStyle(color: secondaryColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
              data: (ytPlaylists) {
                // Combine YT Music playlists + local playlists
                final allPlaylists = [...ytPlaylists, ...localPlaylists];

                if (allPlaylists.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Iconsax.music_playlist,
                          size: 48,
                          color: secondaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No playlists yet',
                          style: TextStyle(color: secondaryColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one to get started',
                          style: TextStyle(color: secondaryColor, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: allPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = allPlaylists[index];
                    final isYtPlaylist = index < ytPlaylists.length;
                    final trackAlreadyIn =
                        playlist.tracks?.any((t) => t.id == widget.track.id) ??
                        false;

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: playlist.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: playlist.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: colorScheme.primaryContainer,
                                  child: Icon(
                                    Iconsax.music_playlist,
                                    color: colorScheme.primary,
                                  ),
                                ),
                        ),
                      ),
                      title: Text(
                        playlist.title,
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            '${playlist.trackCount} songs',
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 13,
                            ),
                          ),
                          if (isYtPlaylist) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.cloud_outlined,
                              size: 14,
                              color: secondaryColor,
                            ),
                          ],
                        ],
                      ),
                      trailing: trackAlreadyIn
                          ? Icon(Icons.check, color: colorScheme.primary)
                          : null,
                      onTap: trackAlreadyIn
                          ? null
                          : () => _addToPlaylist(
                              playlist,
                              isYtPlaylist: isYtPlaylist,
                            ),
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _createAndAdd() async {
    final name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;

    final authState = ref.read(ytMusicAuthStateProvider);

    if (authState.isLoggedIn) {
      // Create playlist on YouTube Music cloud
      final playlistAction = ref.read(ytMusicPlaylistActionProvider);
      try {
        final playlistId = await playlistAction.create(name);
        if (playlistId != null && mounted) {
          // Add track to the newly created playlist
          await playlistAction.addSong(playlistId, widget.track.id);
          // Refresh playlists list
          ref.invalidate(ytMusicSavedPlaylistsProvider);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Created "$name" on YT Music and added "${widget.track.title}"',
              ),
            ),
          );
        } else if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create playlist')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
        }
      }
    } else {
      // Fall back to local playlist if not logged in
      ref.read(localPlaylistsProvider.notifier).createPlaylist(name);
      final playlists = ref.read(localPlaylistsProvider);
      if (playlists.isNotEmpty) {
        ref
            .read(localPlaylistsProvider.notifier)
            .addTrackToPlaylist(playlists.first.id, widget.track);
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created "$name" locally and added "${widget.track.title}"',
          ),
        ),
      );
    }
  }

  void _addToPlaylist(Playlist playlist, {bool isYtPlaylist = false}) async {
    if (isYtPlaylist) {
      // Add to YT Music playlist via API
      final innerTube = ref.read(innerTubeServiceProvider);
      try {
        final success = await innerTube.addToPlaylist(
          playlist.id,
          widget.track.id,
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Added "${widget.track.title}" to "${playlist.title}"'
                    : 'Failed to add to playlist',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
        }
      }
    } else {
      // Add to local playlist
      ref
          .read(localPlaylistsProvider.notifier)
          .addTrackToPlaylist(playlist.id, widget.track);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${widget.track.title}" to "${playlist.title}"'),
        ),
      );
    }
  }
}
