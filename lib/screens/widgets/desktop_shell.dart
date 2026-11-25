import 'dart:async';
import 'dart:io' show Platform;
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
import '../../services/inzx_connect_remote.dart';
import '../../services/inzx_connect_service.dart';
import '../inzx_connect_screen.dart';
import '../jams_screen.dart';
import '../search_screen.dart';
import '../ytmusic_settings_screen.dart';
import 'artist_screen.dart';
import 'desktop_player_bar.dart';
import 'desktop_update_button.dart';
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

/// Whether Connect is covering the selected tab in the player's side pane.
final desktopConnectPaneOpen = ValueNotifier<bool>(false);

/// Whether the now playing view is open between the sidebar and player bar.
final desktopNowPlayingOpen = ValueNotifier<bool>(false);

/// Whether the window is currently the small always-on-top player.
final desktopMiniMode = ValueNotifier<bool>(false);

/// Whether the player has taken over the whole screen, showing the lyrics.
final desktopFullScreen = ValueNotifier<bool>(false);

Future<void> setDesktopFullScreen(bool on) async {
  if (on) NowPlayingScreen.showDesktop();
  desktopFullScreen.value = on;
  await _setWindowFullScreen(on, () => desktopFullScreen.value);
}

/// Whether a video (a podcast episode) has taken over the whole screen. Like
/// [desktopFullScreen] the frame steps aside, but the page stays as it is
/// and shows only its video.
final desktopVideoFullScreen = ValueNotifier<bool>(false);

Future<void> setDesktopVideoFullScreen(bool on) async {
  if (desktopVideoFullScreen.value == on) return;
  desktopVideoFullScreen.value = on;
  await _setWindowFullScreen(on, () => desktopVideoFullScreen.value);
}

/// The window's full screen switches, one at a time: two quick presses must
/// not run the native restyle and resize over each other.
Future<void> _fullScreenQueue = Future<void>.value();

/// What the native window actually is, as opposed to what was last asked
/// for. Leaving a full screen that never happened would have the plugin
/// restore a frame it never saved.
bool _windowFullScreen = false;

Future<void> _setWindowFullScreen(bool on, bool Function() stillWanted) {
  return _fullScreenQueue = _fullScreenQueue
      .catchError((Object _) {})
      .then((_) async {
        if (stillWanted() != on) return; // a later press already undid it
        if (_windowFullScreen == on) return;
        if (on) {
          await _maximizeBeforeFullScreen();
          await windowManager.setFullScreen(true);
        } else {
          await windowManager.setFullScreen(false);
          await _unmaximizeAfterFullScreen();
        }
        _windowFullScreen = on;
        if (on) await _healFullScreenView(stillWanted);
      });
}

/// Whether the window was maximised on the way into full screen, and so is
/// put back to its normal size on the way out.
bool _maximizedForFullScreen = false;

/// On Windows, window_manager only takes a maximised window to full screen
/// cleanly. From a normal window it makes the window frameless first, and the
/// client area then misses the screen's top and right edges, leaving bands
/// of stale pixels there. So a normal window is maximised first and takes
/// the same path as a maximised one.
Future<void> _maximizeBeforeFullScreen() async {
  if (!Platform.isWindows || await windowManager.isMaximized()) return;
  _maximizedForFullScreen = true;
  await windowManager.maximize();
  await _waitForMaximized(true);
}

Future<void> _unmaximizeAfterFullScreen() async {
  if (!_maximizedForFullScreen) return;
  _maximizedForFullScreen = false;
  // The plugin re-maximises a window it took from maximised, by a posted
  // message: wait for that to land, or it would undo the restore.
  await _waitForMaximized(true);
  await windowManager.unmaximize();
}

Future<void> _waitForMaximized(bool maximized) async {
  for (var i = 0; i < 20; i++) {
    if (await windowManager.isMaximized() == maximized) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Now and then the switch leaves Flutter drawing at a size that isn't the
/// window's (the page comes out zoomed and cut off until full screen is left
/// and entered again). Checks once the window has settled, and if Flutter's
/// view disagrees with the real window, does that leave-and-enter itself.
Future<void> _healFullScreenView(bool Function() stillWanted) async {
  for (final wait in const [
    Duration(milliseconds: 200),
    Duration(milliseconds: 800),
  ]) {
    await Future<void>.delayed(wait);
    if (!stillWanted()) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final bounds = await windowManager.getBounds();
    final expected = bounds.size * view.devicePixelRatio;
    final actual = view.physicalSize;
    if ((expected.width - actual.width).abs() <= 2 &&
        (expected.height - actual.height).abs() <= 2) {
      return;
    }
    debugPrint(
      'Full screen: view ${actual.width}x${actual.height} != window '
      '${expected.width}x${expected.height}; switching again',
    );
    await windowManager.setFullScreen(false);
    if (!stillWanted()) return;
    await windowManager.setFullScreen(true);
  }
}

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

/// Space plays and pauses, Ctrl+arrows change the track, F11 toggles the full
/// screen lyrics player and Escape closes the now playing view. Text fields
/// handle these keys first, so typing is unaffected.
class DesktopShortcuts extends ConsumerWidget {
  const DesktopShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            ref.read(playbackTransportProvider).togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            () => ref.read(playbackTransportProvider).skipToNext(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            () => ref.read(playbackTransportProvider).skipToPrevious(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (desktopVideoFullScreen.value) {
            setDesktopVideoFullScreen(false);
          } else if (desktopFullScreen.value) {
            setDesktopFullScreen(false);
          } else {
            NowPlayingScreen.closeDesktop();
          }
        },
        // F11 opens or leaves the full screen lyrics player.
        const SingleActivator(LogicalKeyboardKey.f11): () {
          if (desktopVideoFullScreen.value) {
            setDesktopVideoFullScreen(false);
          } else if (!desktopMiniMode.value) {
            setDesktopFullScreen(!desktopFullScreen.value);
          }
        },
      },
      child: FocusScope(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            final focused = FocusManager.instance.primaryFocus?.context;
            if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
              // Let platform text input insert the space.
              return KeyEventResult.skipRemainingHandlers;
            }
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
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

  static void openSearch(BuildContext context, {required String query}) {
    context.findAncestorStateOfType<_DesktopAppFrameState>()?._openSearch(
      query: query,
    );
  }

  @override
  State<DesktopAppFrame> createState() => _DesktopAppFrameState();
}

class _DesktopAppFrameState extends State<DesktopAppFrame> {
  // The navigator's overlay is inside the frame; tooltips and sliders up here
  // need one of their own.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildFrame);
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  MaterialPageRoute<void>? _searchRoute;
  Timer? _connectPollTimer;

  @override
  void initState() {
    super.initState();
    _initInzxConnect();
  }

  void _initInzxConnect() async {
    try {
      if (!await InzxConnectService.instance.hasSession()) return;
      await _refreshInzxConnect();
      _connectPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        _refreshInzxConnect();
      });
    } catch (_) {}
  }

  Future<void> _refreshInzxConnect() async {
    try {
      if (!await InzxConnectService.instance.hasSession()) return;
      final status = await InzxConnectService.instance.status();
      if (status.devices.isNotEmpty) {
        await InzxConnectRemote.instance.watch(status.devices);
      }
    } catch (_) {}
  }

  void _openSearch({String? query}) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    if (query != null) {
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
      _searchFocusNode.unfocus();
    }
    final existing = _searchRoute;
    if (existing != null && existing.isActive) {
      if (!existing.isCurrent) {
        navigator.popUntil((route) => route == existing);
      }
      return;
    }
    final route = MaterialPageRoute<void>(
      requestFocus: false,
      builder: (_) => SearchScreen(
        desktopInput: (
          controller: _searchController,
          focusNode: _searchFocusNode,
        ),
      ),
    );
    _searchRoute = route;
    unawaited(
      navigator.push(route).then((_) {
        if (!mounted || _searchRoute != route) return;
        _searchRoute = null;
        _searchFocusNode.unfocus();
        _searchController.clear();
      }),
    );
  }

  @override
  void dispose() {
    _connectPollTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DesktopAppFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  Widget _buildFrame(BuildContext context) {
    final frame = Material(
      color: Colors.transparent,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          desktopShellVisible,
          desktopMiniMode,
          desktopFullScreen,
          desktopVideoFullScreen,
        ]),
        builder: (context, _) {
          final showShell = desktopShellVisible.value &&
              !desktopFullScreen.value &&
              !desktopVideoFullScreen.value;
          final mini = desktopMiniMode.value;
          return Stack(
            children: [
              const Positioned.fill(child: _DesktopBackdrop()),
              // Keep the navigation stack and scroll positions in mini mode.
              Visibility(
                visible: !mini,
                maintainState: true,
                child: _MinimumSizeLayout(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          if (showShell)
                            _DesktopTopBar(
                              showShell: true,
                              search: _SearchPill(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onOpen: _openSearch,
                              ),
                            ),
                          Expanded(
                            child: Row(
                              children: [
                                if (showShell) const _DesktopSidebar(),
                                Expanded(
                                  child: _CenterPane(
                                    topInset: desktopShellVisible.value
                                        ? 0
                                        : _kTopBarHeight,
                                    child: widget.child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showShell) DesktopPlayerBar(showControls: !mini),
                        ],
                      ),
                      // Onboarding runs edge to edge behind the window buttons.
                      if (!desktopShellVisible.value)
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

/// The album-coloured background behind the entire window. The top bar,
/// sidebar and pages are all see-through, so they share one colour and one
/// gradient from the very top edge.
class _DesktopBackdrop extends ConsumerWidget {
  const _DesktopBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final accent = hasAlbumColors
        ? albumColors.accent
        : Theme.of(context).colorScheme.primary;
    final Color background;
    if (hasAlbumColors && isDark) {
      background = albumColors.backgroundSecondary;
    } else {
      background = isDark ? InzxColors.darkBackground : InzxColors.background;
    }
    final strength = isDark ? (hasAlbumColors ? 0.4 : 0.35) : 0.22;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      color: background,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          height: 320,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: strength),
                accent.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
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
          // Pages that don't set a background show the backdrop too.
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(scaffoldBackgroundColor: Colors.transparent),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar({required this.showShell, this.search});

  final bool showShell;
  final Widget? search;

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
            const SizedBox(width: 18),
            Image.asset('assets/logo_transparent.png', width: 42, height: 42),
            const SizedBox(width: 8),
            // The wordmark's letters are white, so light themes keep text.
            if (isDark)
              ClipRect(
                child: Align(
                  // The image has wide transparent margins around the letters.
                  widthFactor: 0.7,
                  heightFactor: 0.56,
                  child: Image.asset(
                    'assets/text.png',
                    height: 33,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              )
            else
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DragToMoveArea(child: SizedBox.expand()),
                if (showShell)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, right: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: search,
                    ),
                  ),
              ],
            ),
          ),
          if (showShell) ...[
            DesktopUpdateButton(foreground: foreground),
            _JamsButton(foreground: foreground),
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

class _SearchPill extends ConsumerWidget {
  const _SearchPill({
    required this.controller,
    required this.focusNode,
    required this.onOpen,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 38,
          child: ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: 14),
              onTap: onOpen,
              onChanged: (_) => onOpen(),
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  ref
                      .read(searchHistoryProvider.notifier)
                      .addSearch(query.trim());
                }
              },
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search songs, albums, artists, podcasts',
                hintStyle: TextStyle(color: muted, fontSize: 14),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 42,
                  minHeight: 38,
                ),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: muted),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        icon: Icon(Icons.close, size: 18, color: muted),
                        onPressed: () {
                          controller.clear();
                          focusNode.requestFocus();
                          onOpen();
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens Jams. While a jam is on, the icon lights up in the accent colour
/// and carries the number of people listening.
class _JamsButton extends ConsumerWidget {
  const _JamsButton({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentJamSessionProvider).valueOrNull;
    final accent = ref.watch(effectiveAccentColorProvider);
    final count = session?.participants.length ?? 0;
    final active = session != null;

    final icon = Icon(
      Iconsax.profile_2user,
      color: active ? accent : foreground,
      size: 20,
    );

    return IconButton(
      tooltip: active ? 'Jam on · $count listening' : 'Jams',
      style: active
          ? IconButton.styleFrom(
              backgroundColor: accent.withValues(alpha: 0.16),
            )
          : null,
      onPressed: () {
        final context = rootNavigatorKey.currentContext;
        if (context != null) JamsScreen.open(context);
      },
      icon: active
          ? Badge(
              label: Text('$count'),
              backgroundColor: accent,
              textColor:
                  ThemeData.estimateBrightnessForColor(accent) ==
                      Brightness.dark
                  ? Colors.white
                  : Colors.black,
              offset: const Offset(10, -8),
              child: icon,
            )
          : icon,
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
      onTap: () {
        // Settings has no back button here, so never stack a second one.
        _showFirstRoute();
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const YTMusicSettingsScreen()),
        );
      },
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
      (Icons.explore_outlined, Icons.explore_rounded, l10n.explore),
      (Icons.library_music_outlined, Icons.library_music_rounded, l10n.library),
      (Icons.folder_outlined, Icons.folder_rounded, l10n.folders),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: collapsed ? _kSidebarCollapsedWidth : _kSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The expanded rows need room for the artwork and hover action.
            // Keep the compact layout while the sidebar grows into that space.
            final compact = collapsed || constraints.maxWidth < 120;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, tab) in tabs.indexed)
                  _SidebarTab(
                    icon: index == currentTab ? tab.$2 : tab.$1,
                    label: tab.$3,
                    selected: index == currentTab,
                    collapsed: compact,
                    accent: accent,
                    isDark: isDark,
                    onTap: () => _selectTab(ref, index),
                  ),
                ListenableBuilder(
                  listenable: InzxConnectRemote.instance,
                  builder: (context, _) {
                    final remote = InzxConnectRemote.instance;
                    final hasActive = remote.activePlayback != null ||
                        remote.pairedDevices.any((d) => remote.isOnline(d.id));
                    if (!hasActive && library.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.14),
                          ),
                          const SizedBox(height: 8),
                          _DesktopConnectSidebarCard(
                            compact: compact,
                            accent: accent,
                            isDark: isDark,
                          ),
                          if (library.isNotEmpty)
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: library.length,
                                itemBuilder: (context, index) {
                                  final entry = library[index];
                                  return _LibraryTile(
                                    entry: entry,
                                    pinned: pinned.contains(entry.key),
                                    collapsed: compact,
                                    accent: accent,
                                    isDark: isDark,
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
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

/// A pulsating blinking dot indicating active connection.
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot({required this.color});

  final Color color;

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.75 * _animation.value),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renders an active Inzx Connect device indicator card at the top of the
/// sidebar navigation, appearing only when a remote device is online or active.
class _DesktopConnectSidebarCard extends StatelessWidget {
  const _DesktopConnectSidebarCard({
    required this.compact,
    required this.accent,
    required this.isDark,
  });

  final bool compact;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InzxConnectRemote.instance,
      builder: (context, _) {
        final remote = InzxConnectRemote.instance;
        final activePlayback = remote.activePlayback;
        final onlineDevice = remote.pairedDevices
            .where((d) => remote.isOnline(d.id))
            .firstOrNull;
        final groupDevice = remote.isPlayingOnBoth
            ? remote.pairedDevices
                .where((d) => remote.isGroupedWith(d.id))
                .firstOrNull
            : null;
        final activeDevice =
            groupDevice ?? activePlayback?.device ?? onlineDevice;

        if (activeDevice == null) {
          return const SizedBox.shrink();
        }

        final isPlayingOnTarget = remote.isOutputSelected(activeDevice.id);
        final String statusPrefix;
        if (remote.isPlayingOnBoth) {
          statusPrefix = 'Playing on both with ';
        } else if (isPlayingOnTarget) {
          final peerPlayback = remote.playbackOf(activeDevice.id);
          statusPrefix =
              peerPlayback?.isPlaying == false ? 'Paused on ' : 'Playing on ';
        } else if (activePlayback != null) {
          statusPrefix = activePlayback.playback.isPlaying
              ? 'Playing on '
              : 'Paused on ';
        } else {
          statusPrefix = 'Connected to ';
        }

        void onTap() {
          desktopConnectPaneOpen.value = true;
          NowPlayingScreen.showDesktop();
        }

        final tooltipMessage =
            'Inzx Connect · $statusPrefix${activeDevice.label}';

        if (compact) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Tooltip(
              message: tooltipMessage,
              child: Material(
                color: accent.withValues(alpha: isDark ? 0.12 : 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: accent.withValues(alpha: isDark ? 0.35 : 0.45),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Icon(
                        InzxConnectScreen.icon,
                        size: 20,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Material(
            color: accent.withValues(alpha: isDark ? 0.10 : 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: accent.withValues(alpha: isDark ? 0.30 : 0.38),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              hoverColor: accent.withValues(alpha: 0.10),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(InzxConnectScreen.icon, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          'Inzx Connect',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        _BlinkingDot(color: accent),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          color: (isDark ? Colors.white : Colors.black87)
                              .withValues(alpha: 0.7),
                        ),
                        children: [
                          TextSpan(text: statusPrefix),
                          TextSpan(
                            text: activeDevice.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
