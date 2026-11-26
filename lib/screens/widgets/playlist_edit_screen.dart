import 'dart:typed_data';
import '../../core/utils/platform_utils.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/l10n/app_localizations_x.dart';
import '../../core/services/cache/hive_service.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'playlist_screen.dart' show PlaylistTrackSort;
import 'square_image_cropper.dart';

/// Top-level isolate function for inspecting image dimensions
(int, int)? _decodeImageDimensions(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return (decoded.width, decoded.height);
  } catch (_) {
    return null;
  }
}

/// Full-screen editor for an owned YouTube Music playlist: cover, title,
/// description, privacy, and an inline drag-to-reorder song list with a sort
/// control. Reorders sync live and are written straight into the cache so the
/// playlist screen behind reflects them immediately.
class PlaylistEditScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistEditScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

class _PlaylistEditScreenState extends ConsumerState<PlaylistEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late String _privacy;
  Uint8List? _rawPickedImage;
  Uint8List? _pickedImage;
  late List<Track> _tracks;
  PlaylistTrackSort _sort = PlaylistTrackSort.defaultOrder;
  bool _saving = false;
  bool _orderChanged = false;
  Future<void> _moveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.playlist.title);
    _descController =
        TextEditingController(text: widget.playlist.description ?? '');
    _privacy = (widget.playlist.privacy ?? 'PRIVATE').toUpperCase();
    if (!const ['PUBLIC', 'PRIVATE', 'UNLISTED'].contains(_privacy)) {
      _privacy = 'PRIVATE';
    }
    _tracks = List<Track>.from(widget.playlist.tracks ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  String get _playlistId => widget.playlist.id;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<Track> _displayTracks() {
    if (_sort == PlaylistTrackSort.defaultOrder) return _tracks;
    final sorted = List<Track>.from(_tracks);
    switch (_sort) {
      case PlaylistTrackSort.title:
        sorted.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistTrackSort.artist:
        sorted.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case PlaylistTrackSort.duration:
        sorted.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case PlaylistTrackSort.defaultOrder:
        break;
    }
    return sorted;
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    late Track moved;
    setState(() {
      moved = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, moved);
      _orderChanged = true;
    });

    final setVideoId = moved.setVideoId;
    if (setVideoId == null || setVideoId.isEmpty) {
      _showSnack("Couldn't reorder this track — reopen the playlist and retry.");
      return;
    }
    final successor =
        newIndex + 1 < _tracks.length ? _tracks[newIndex + 1].setVideoId : null;

    // Reflect the new order on the playlist screen right away (server can lag).
    patchPlaylistCache(_playlistId, order: _tracks);
    ref.invalidate(ytMusicPlaylistProvider(_playlistId));

    final action = ref.read(ytMusicPlaylistActionProvider);
    _moveQueue = _moveQueue.then((_) async {
      final ok = await action.moveSong(
        _playlistId,
        setVideoId,
        successorSetVideoId: successor,
      );
      if (!ok) _showSnack('Failed to save new order.');
    });
  }

  Future<void> _openCropper(Uint8List bytes) async {
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => SquareImageCropper(imageBytes: bytes),
      ),
    );
    if (cropped != null && mounted) {
      setState(() => _pickedImage = cropped);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final dims = await compute(_decodeImageDimensions, bytes);
    if (!mounted) return;

    _rawPickedImage = bytes;

    if (dims != null && (dims.$1 - dims.$2).abs() > 2) {
      // Non-square image -> open interactive 1:1 cropper with centered framing
      await _openCropper(bytes);
    } else {
      // Already square
      setState(() => _pickedImage = bytes);
    }
  }

  Future<void> _save() async {
    final action = ref.read(ytMusicPlaylistActionProvider);
    final newTitle = _titleController.text.trim();
    final newDesc = _descController.text.trim();

    final titleArg =
        (newTitle.isNotEmpty && newTitle != widget.playlist.title)
            ? newTitle
            : null;
    final descArg =
        newDesc != (widget.playlist.description ?? '') ? newDesc : null;
    final privacyArg =
        _privacy != (widget.playlist.privacy ?? '').toUpperCase()
            ? _privacy
            : null;
    final coverChanged = _pickedImage != null;

    if (titleArg == null &&
        descArg == null &&
        privacyArg == null &&
        !coverChanged) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    bool ok = true;
    if (titleArg != null || descArg != null || privacyArg != null) {
      ok = await action.editMetadata(
        _playlistId,
        title: titleArg,
        description: descArg,
        privacyStatus: privacyArg,
      );
    }
    if (ok && coverChanged) {
      ok = await action.uploadImage(_playlistId, _pickedImage!);
    }

    if (ok) {
      if (coverChanged) {
        // A new cover URL is only known after a fetch, so drop the cache and
        // refetch (the server already has the synced reorder by now).
        for (final id in {
          _playlistId,
          _playlistId.startsWith('VL')
              ? _playlistId.substring(2)
              : 'VL$_playlistId',
        }) {
          try {
            HiveService.playlistsBox.delete(id);
          } catch (_) {}
        }
      } else {
        patchPlaylistCache(
          _playlistId,
          order: _orderChanged ? _tracks : null,
          title: titleArg,
          description: descArg,
          privacy: privacyArg,
        );
      }
      ref.invalidate(ytMusicPlaylistProvider(_playlistId));
      ref.invalidate(ytMusicSavedPlaylistsProvider);
    }

    if (!mounted) return;
    Navigator.pop(context);
    _showSnack(ok ? 'Playlist updated' : 'Failed to update playlist');
  }

  void _showSortSheet(bool isDark, Color accent) {
    final textColor = isDark ? Colors.white : Colors.black87;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget tile(PlaylistTrackSort value, String label, IconData icon) {
          final selected = _sort == value;
          return ListTile(
            leading: Icon(icon, color: selected ? accent : textColor),
            title: Text(label, style: TextStyle(color: textColor)),
            trailing:
                selected ? Icon(Icons.check_rounded, color: accent) : null,
            onTap: () {
              setState(() => _sort = value);
              Navigator.pop(ctx);
            },
          );
        }

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                tile(PlaylistTrackSort.defaultOrder, 'Custom order',
                    Icons.reorder_rounded),
                tile(PlaylistTrackSort.title, 'Name', Icons.sort_by_alpha),
                tile(PlaylistTrackSort.artist, 'Artist', Icons.person_rounded),
                tile(PlaylistTrackSort.duration, 'Duration',
                    Icons.access_time_rounded),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = ref.watch(effectiveAccentColorProvider);
    final textColor = isDark ? Colors.white : colorScheme.onSurface;
    final secondary = textColor.withValues(alpha: 0.55);
    final l10n = context.l10n;

    final displayTracks = _displayTracks();
    final reorderable = _sort == PlaylistTrackSort.defaultOrder;

    return Scaffold(
      backgroundColor: desktopPageBackground(isDark ? Colors.black : colorScheme.surface),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Edit playlist',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.only(right: 18),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Cover
                  Center(
                    child: GestureDetector(
                      onTap: _saving ? null : _pickImage,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 130,
                              height: 130,
                              child: _pickedImage != null
                                  ? Image.memory(_pickedImage!,
                                      fit: BoxFit.cover)
                                  : (widget.playlist.thumbnailUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl:
                                              widget.playlist.thumbnailUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: isDark
                                              ? Colors.grey[800]
                                              : Colors.grey[300],
                                        )),
                            ),
                          ),
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                            child: const Icon(Icons.photo_camera_rounded,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: _pickedImage != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _saving ? null : _pickImage,
                                child: Text('Change image',
                                    style: TextStyle(
                                        color: accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('•',
                                    style: TextStyle(
                                        color: secondary, fontSize: 12)),
                              ),
                              GestureDetector(
                                onTap: _saving
                                    ? null
                                    : () => _openCropper(
                                        _rawPickedImage ?? _pickedImage!),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.crop_rounded,
                                        size: 13, color: accent),
                                    const SizedBox(width: 4),
                                    Text('Adjust crop',
                                        style: TextStyle(
                                            color: accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : GestureDetector(
                            onTap: _saving ? null : _pickImage,
                            child: Text('Tap to change cover',
                                style:
                                    TextStyle(color: secondary, fontSize: 12)),
                          ),
                  ),
                  const SizedBox(height: 18),
                  _field(
                    controller: _titleController,
                    label: 'Title',
                    hint: 'Playlist name',
                    textColor: textColor,
                    accent: accent,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    controller: _descController,
                    label: 'Description',
                    hint: 'Add an optional description',
                    textColor: textColor,
                    accent: accent,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  Text('Privacy',
                      style: TextStyle(
                          color: secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in const [
                        ('PUBLIC', 'Public'),
                        ('UNLISTED', 'Unlisted'),
                        ('PRIVATE', 'Private'),
                      ])
                        ChoiceChip(
                          label: Text(option.$2),
                          selected: _privacy == option.$1,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _privacy = option.$1),
                          selectedColor: accent.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            color: _privacy == option.$1
                                ? textColor
                                : secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Songs header + sort
                  Row(
                    children: [
                      Text(
                        'Songs',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${_tracks.length}',
                          style: TextStyle(color: secondary, fontSize: 14)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showSortSheet(isDark, accent),
                        icon: Icon(Icons.sort_rounded,
                            size: 18, color: accent),
                        label: Text(
                          switch (_sort) {
                            PlaylistTrackSort.defaultOrder => 'Custom',
                            PlaylistTrackSort.title => 'Name',
                            PlaylistTrackSort.artist => 'Artist',
                            PlaylistTrackSort.duration => 'Duration',
                          },
                          style: TextStyle(color: accent),
                        ),
                      ),
                    ],
                  ),
                  if (reorderable)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        'Drag the handles to reorder. Saved automatically.',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        'Switch to Custom order to drag songs.',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (reorderable)
            SliverReorderableList(
              itemCount: displayTracks.length,
              onReorderItem: _onReorder,
              proxyDecorator: (child, index, animation) => Material(
                color:
                    (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                child: child,
              ),
              itemBuilder: (context, index) => _songTile(
                displayTracks[index],
                index,
                isDark,
                textColor,
                secondary,
                draggable: true,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _songTile(
                  displayTracks[index],
                  index,
                  isDark,
                  textColor,
                  secondary,
                  draggable: false,
                ),
                childCount: displayTracks.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  Widget _songTile(
    Track track,
    int index,
    bool isDark,
    Color textColor,
    Color secondary, {
    required bool draggable,
  }) {
    final subtitle = track.formattedDuration.isNotEmpty
        ? '${track.artist} • ${track.formattedDuration}'
        : track.artist;
    return Material(
      key: ValueKey(track.setVideoId ?? '${track.id}_$index'),
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 46,
            height: 46,
            child: track.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: track.thumbnailUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    errorWidget: (_, _, _) => Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[300]),
                  )
                : Container(
                    color: isDark ? Colors.grey[800] : Colors.grey[300]),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: secondary, fontSize: 13),
        ),
        trailing: draggable
            ? ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child:
                      Icon(Icons.drag_handle_rounded, color: secondary),
                ),
              )
            : null,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color textColor,
    required Color accent,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: textColor.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
          cursorColor: accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
                color: textColor.withValues(alpha: 0.35), fontSize: 14),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: textColor.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: textColor.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ],
    );
  }
}
