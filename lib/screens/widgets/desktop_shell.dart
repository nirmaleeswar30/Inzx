import 'dart:math' show max;
import 'dart:ui' show PointerDeviceKind;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/utils/platform_utils.dart';
import '../../main.dart' show rootNavigatorKey;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/desktop/desktop_bootstrap.dart'
    show kDesktopMinWindowSize;
import '../jams_screen.dart';
import '../search_screen.dart';
import '../ytmusic_settings_screen.dart';
import 'artist_screen.dart';
import 'desktop_player_bar.dart';
import 'now_playing_screen.dart';
import 'playlist_screen.dart';
import 'podcast_screen.dart';

const double _kTopBarHeight = 56;
const double _kSidebarWidth = 240;
const double _kSidebarCollapsedWidth = 72;

/// Below this window width the sidebar always shows icons only.
const double _kSidebarAutoCollapseWidth = 900;

/// False during onboarding, which has only the window buttons around it.
final desktopShellVisible = ValueNotifier<bool>(true);

/// Which tab the player's right-hand panel shows: Up Next, Lyrics or Related.
final desktopNowPlayingTab = ValueNotifier<int>(0);

/// Whether the now playing view is open between the sidebar and player bar.
final desktopNowPlayingOpen = ValueNotifier<bool>(false);

/// Whether the window is currently the small always-on-top player.
final desktopMiniMode = ValueNotifier<bool>(false);

final desktopTabProvider = StateProvider<int>((ref) => 0);
final desktopSidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Lets a mouse drag the app's horizontal shelves, which the wheel can't reach.
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  // Flutter's automatic desktop scrollbars assert on the player's panes, which
  // share one scroll controller. The wheel and dragging both still scroll.
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Space plays and pauses, Ctrl+arrows change the track, Escape closes the now
/// playing view. Text fields handle these keys first, so typing is unaffected.
class DesktopShortcuts extends ConsumerWidget {
  const DesktopShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(audioPlayerServiceProvider);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): player.togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            player.skipToNext,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            player.skipToPrevious,
        const SingleActivator(LogicalKeyboardKey.escape):
            NowPlayingScreen.closeDesktop,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

void _showFirstRoute() {
  rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
}

/// The window's permanent parts: the top bar, the sidebar and the player bar.
///
/// They sit above the app's navigator, so every page pushed inside [child],
/// the now playing view included, stays between them.
class DesktopAppFrame extends StatefulWidget {
  const DesktopAppFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopAppFrame> createState() => _DesktopAppFrameState();
}

class _DesktopAppFrameState extends State<DesktopAppFrame> {
  // The navigator's overlay is inside the frame; tooltips and sliders up here
  // need one of their own.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildFrame);

  @override
  void didUpdateWidget(DesktopAppFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  Widget _buildFrame(BuildContext context) {
    final frame = Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : InzxColors.background,
      child: ListenableBuilder(
        listenable: Listenable.merge([desktopShellVisible, desktopMiniMode]),
        builder: (context, _) {
          final showShell = desktopShellVisible.value;
          final mini = desktopMiniMode.value;
          return Stack(
            children: [
              // Offstage rather than removed, so pages and scroll positions
              // are all still there when the mini player is closed.
              Offstage(
                offstage: mini,
                child: _MinimumSizeLayout(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          if (showShell) const _DesktopTopBar(showShell: true),
                          Expanded(
                            child: Row(
                              children: [
                                if (showShell) const _DesktopSidebar(),
                                Expanded(
                                  child: _CenterPane(
                                    topInset: showShell ? 0 : _kTopBarHeight,
                                    child: widget.child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showShell) const DesktopPlayerBar(),
                        ],
                      ),
                      // Onboarding runs edge to edge behind the window buttons.
                      if (!showShell)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _DesktopTopBar(showShell: false),
                        ),
                    ],
                  ),
                ),
              ),
              if (mini) const Positioned.fill(child: DesktopPopoutPlayer()),
            ],
          );
        },
      ),
    );
    return isLinuxDesktop ? DragToResizeArea(child: frame) : frame;
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }
}

/// Lays the full window out at no less than its minimum size, so it isn't
/// squeezed while the window is the small mini player.
class _MinimumSizeLayout extends StatelessWidget {
  const _MinimumSizeLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = max(constraints.maxWidth, kDesktopMinWindowSize.width);
        final height = max(constraints.maxHeight, kDesktopMinWindowSize.height);
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: child,
        );
      },
    );
  }
}

/// Gives pages their real size, so anything sized from MediaQuery lays out for
/// the space between the sidebar and the window edge.
class _CenterPane extends StatelessWidget {
  const _CenterPane({required this.child, required this.topInset});

  final Widget child;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: constraints.biggest,
            padding: EdgeInsets.only(top: topInset),
            viewPadding: EdgeInsets.only(top: topInset),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar({required this.showShell});

  final bool showShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Onboarding's background is dark in either theme.
    final brightness = showShell
        ? Theme.of(context).brightness
        : Brightness.dark;
    final isDark = brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black87;

    return SizedBox(
      height: _kTopBarHeight,
      child: Row(
        children: [
          if (showShell) ...[
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(Icons.menu_rounded, color: foreground),
              onPressed: () {
                final collapsed = ref.read(
                  desktopSidebarCollapsedProvider.notifier,
                );
                collapsed.state = !collapsed.state;
              },
            ),
            const SizedBox(width: 6),
            Image.asset('assets/logo_transparent.png', width: 30, height: 30),
            const SizedBox(width: 8),
            Text(
              'Inzx',
              style: TextStyle(
                color: foreground,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          Expanded(
            child: DragToMoveArea(
              child: SizedBox.expand(
                child: showShell
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Center(child: _SearchPill(isDark: isDark)),
                      )
                    : null,
              ),
            ),
          ),
          if (showShell) ...[
            IconButton(
              icon: Icon(Iconsax.profile_2user, color: foreground, size: 20),
              tooltip: 'Jams',
              onPressed: () {
                final context = rootNavigatorKey.currentContext;
                if (context != null) JamsScreen.open(context);
              },
            ),
            const SizedBox(width: 6),
            const _ProfileButton(),
            const SizedBox(width: 12),
          ],
          Align(
            alignment: Alignment.topCenter,
            child: _WindowButtons(brightness: brightness),
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white60 : Colors.black54;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => rootNavigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search_rounded, size: 20, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.searchMusicHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(appAccountProvider);
    final avatarUrl = account?.avatarUrl;
    final accent = ref.watch(effectiveAccentColorProvider);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const YTMusicSettingsScreen()),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: accent,
        backgroundImage: avatarUrl != null
            ? CachedNetworkImageProvider(avatarUrl)
            : null,
        child: avatarUrl == null
            ? Text(
                account?.initials ?? 'U',
                style: TextStyle(
                  color: InzxColors.contrastTextOn(accent),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons({required this.brightness});

  final Brightness brightness;

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: widget.brightness,
          onPressed: windowManager.minimize,
        ),
        if (_maximized)
          WindowCaptionButton.unmaximize(
            brightness: widget.brightness,
            onPressed: windowManager.unmaximize,
          )
        else
          WindowCaptionButton.maximize(
            brightness: widget.brightness,
            onPressed: windowManager.maximize,
          ),
        WindowCaptionButton.close(
          brightness: widget.brightness,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

enum DesktopLibraryType { playlist, artist, podcast }

/// A playlist, artist or podcast listed in the sidebar.
class DesktopLibraryEntry {
  const DesktopLibraryEntry({
    required this.type,
    required this.id,
    required this.title,
    this.thumbnailUrl,
  });

  final DesktopLibraryType type;
  final String id;
  final String title;
  final String? thumbnailUrl;

  String get key => '${type.name}:$id';
}

/// Keys of the pinned sidebar entries, most recently pinned first.
class DesktopPinnedLibrary extends StateNotifier<List<String>> {
  DesktopPinnedLibrary() : super(const []) {
    _load();
  }

  static const _prefKey = 'desktop_pinned_library';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_prefKey) ?? const [];
  }

  Future<void> toggle(String key) async {
    state = state.contains(key)
        ? state.where((k) => k != key).toList()
        : [key, ...state];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, state);
  }
}

final desktopPinnedLibraryProvider =
    StateNotifierProvider<DesktopPinnedLibrary, List<String>>(
      (ref) => DesktopPinnedLibrary(),
    );

/// Everything in the user's library, pinned entries first.
final desktopLibraryProvider = Provider<List<DesktopLibraryEntry>>((ref) {
  final byKey = <String, DesktopLibraryEntry>{};
  void add(DesktopLibraryEntry entry) =>
      byKey.putIfAbsent(entry.key, () => entry);

  void addPlaylists(Iterable<Playlist> playlists, DesktopLibraryType type) {
    for (final playlist in playlists) {
      add(
        DesktopLibraryEntry(
          type: type,
          id: playlist.id,
          title: playlist.title,
          thumbnailUrl: playlist.thumbnailUrl,
        ),
      );
    }
  }

  void addArtists(Iterable<Artist> artists) {
    for (final artist in artists) {
      add(
        DesktopLibraryEntry(
          type: DesktopLibraryType.artist,
          id: artist.id,
          title: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        ),
      );
    }
  }

  addPlaylists(ref.watch(localPlaylistsProvider), DesktopLibraryType.playlist);
  addPlaylists(
    ref.watch(ytMusicSavedPlaylistsProvider).valueOrNull ?? const [],
    DesktopLibraryType.playlist,
  );
  addArtists(
    ref.watch(ytMusicLibrarySubscriptionsProvider).valueOrNull ?? const [],
  );
  addArtists(ref.watch(ytMusicLibraryArtistsProvider).valueOrNull ?? const []);
  addPlaylists(
    ref.watch(ytMusicSavedPodcastsProvider).valueOrNull ?? const [],
    DesktopLibraryType.podcast,
  );

  final pinned = ref.watch(desktopPinnedLibraryProvider);
  return [
    for (final key in pinned)
      if (byKey[key] != null) byKey[key]!,
    ...byKey.values.where((entry) => !pinned.contains(entry.key)),
  ];
});

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar();

  void _selectTab(WidgetRef ref, int index) {
    _showFirstRoute();
    ref.read(desktopTabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(effectiveAccentColorProvider);
    final currentTab = ref.watch(desktopTabProvider);
    final library = ref.watch(desktopLibraryProvider);
    final pinned = ref.watch(desktopPinnedLibraryProvider);
    final collapsed =
        ref.watch(desktopSidebarCollapsedProvider) ||
        MediaQuery.sizeOf(context).width < _kSidebarAutoCollapseWidth;

    final tabs = [
      (Icons.home_outlined, Icons.home_rounded, l10n.home),
      (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
      (Icons.library_music_outlined, Icons.library_music_rounded, l10n.library),
      (Icons.folder_outlined, Icons.folder_rounded, l10n.folders),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: collapsed ? _kSidebarCollapsedWidth : _kSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, tab) in tabs.indexed)
              _SidebarTab(
                icon: index == currentTab ? tab.$2 : tab.$1,
                label: tab.$3,
                selected: index == currentTab,
                collapsed: collapsed,
                accent: accent,
                isDark: isDark,
                onTap: () => _selectTab(ref, index),
              ),
            if (library.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.14,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: library.length,
                  itemBuilder: (context, index) {
                    final entry = library[index];
                    return _LibraryTile(
                      entry: entry,
                      pinned: pinned.contains(entry.key),
                      collapsed: collapsed,
                      accent: accent,
                      isDark: isDark,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarTab extends StatelessWidget {
  const _SidebarTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = isDark ? Colors.white : Colors.black87;
    final color = selected ? accent : base.withValues(alpha: 0.8);

    final tile = Material(
      color: selected
          ? (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: collapsed
              ? Icon(icon, color: color)
              : Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(icon, color: color),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: collapsed ? Tooltip(message: label, child: tile) : tile,
    );
  }
}

class _LibraryTile extends ConsumerStatefulWidget {
  const _LibraryTile({
    required this.entry,
    required this.pinned,
    required this.collapsed,
    required this.accent,
    required this.isDark,
  });

  final DesktopLibraryEntry entry;
  final bool pinned;
  final bool collapsed;
  final Color accent;
  final bool isDark;

  @override
  ConsumerState<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends ConsumerState<_LibraryTile> {
  bool _hovered = false;

  void _open() {
    _showFirstRoute();
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final entry = widget.entry;
    switch (entry.type) {
      case DesktopLibraryType.artist:
        ArtistScreen.open(
          context,
          artistId: entry.id,
          name: entry.title,
          thumbnailUrl: entry.thumbnailUrl,
        );
      case DesktopLibraryType.podcast when entry.id.startsWith('MPSP'):
        PodcastScreen.open(
          context,
          podcastId: entry.id,
          title: entry.title,
          thumbnailUrl: entry.thumbnailUrl,
        );
      case DesktopLibraryType.podcast:
      case DesktopLibraryType.playlist:
        PlaylistScreen.open(
          context,
          playlistId: entry.id,
          title: entry.title,
          thumbnailUrl: entry.thumbnailUrl,
        );
    }
  }

  void _togglePin() {
    ref.read(desktopPinnedLibraryProvider.notifier).toggle(widget.entry.key);
  }

  String get _typeLabel => switch (widget.entry.type) {
    DesktopLibraryType.playlist => 'Playlist',
    DesktopLibraryType.artist => 'Artist',
    DesktopLibraryType.podcast => 'Podcast',
  };

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final base = widget.isDark ? Colors.white : Colors.black87;
    final isArtist = entry.type == DesktopLibraryType.artist;
    final radius = BorderRadius.circular(isArtist ? 22 : 6);

    final art = ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: 44,
        height: 44,
        child: entry.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: entry.thumbnailUrl!,
                memCacheWidth: 132,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _artFallback(base),
              )
            : _artFallback(base),
      ),
    );

    final Widget content;
    if (widget.collapsed) {
      content = Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            art,
            if (widget.pinned)
              Positioned(
                right: -3,
                top: -3,
                child: Icon(Icons.push_pin, size: 13, color: widget.accent),
              ),
          ],
        ),
      );
    } else {
      content = Row(
        children: [
          const SizedBox(width: 4),
          art,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: base,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (widget.pinned) ...[
                      Icon(Icons.push_pin, size: 11, color: widget.accent),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        _typeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: base.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_hovered)
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: widget.pinned ? 'Unpin' : 'Pin',
              onPressed: _togglePin,
              icon: Icon(
                widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: widget.pinned
                    ? widget.accent
                    : base.withValues(alpha: 0.7),
              ),
            ),
        ],
      );
    }

    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _open,
        // A collapsed row has no room for the button.
        onSecondaryTap: _togglePin,
        child: SizedBox(height: 56, child: content),
      ),
    );

    return widget.collapsed
        ? Tooltip(
            message:
                '${entry.title}\nRight-click to '
                '${widget.pinned ? 'unpin' : 'pin'}',
            child: tile,
          )
        : tile;
  }

  Widget _artFallback(Color base) => ColoredBox(
    color: base.withValues(alpha: 0.1),
    child: Icon(
      widget.entry.type == DesktopLibraryType.artist
          ? Icons.person_rounded
          : Icons.queue_music_rounded,
      color: base.withValues(alpha: 0.6),
      size: 22,
    ),
  );
}
