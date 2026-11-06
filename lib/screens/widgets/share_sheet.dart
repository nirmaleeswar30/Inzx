import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_localizations_x.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/cache/hive_service.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/album_color_extractor.dart';
import '../../services/deep_link_handler.dart';
import '../../services/local_artwork_service.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/share/share_card_renderer.dart';
import '../../services/share/share_targets.dart';
import '../../services/tagger/media_tagger.dart';
import 'share_card.dart';

/// One line of lyrics. [timeMs] is null when the source has no timing.
typedef LyricEntry = ({String text, int? timeMs});

/// Lyrics from a cached LRC or plain string, one entry per line, with
/// timestamps, word timings and section tags gone.
@visibleForTesting
List<LyricEntry> lyricEntriesFrom(String raw) {
  final tags = RegExp(r'\[[^\]]*\]|<[^>]*>');
  final stamp = RegExp(r'^\s*\[(\d+):(\d+(?:\.\d+)?)\]');
  final entries = <LyricEntry>[];
  for (final line in raw.split('\n')) {
    final text = line.replaceAll(tags, '').trim();
    if (text.isEmpty) continue;
    final match = stamp.firstMatch(line);
    entries.add((
      text: text,
      timeMs: match == null
          ? null
          : int.parse(match[1]!) * 60000 +
                (double.parse(match[2]!) * 1000).round(),
    ));
  }
  return entries;
}

/// The line being sung at [positionMs]: the last one that has started. The
/// first line before the song reaches any, or when lines have no timing.
@visibleForTesting
int currentLineIndex(List<LyricEntry> lines, int positionMs) {
  var current = 0;
  for (var i = 0; i < lines.length; i++) {
    final time = lines[i].timeMs;
    if (time != null && time <= positionMs) current = i;
  }
  return current;
}

/// The share sheet for a song: a live card preview, its style and theme, and
/// where to send it. Inzx links are what get shared; the YouTube Music link is
/// one of the targets.
class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet._({required this.track});

  final Track track;

  static Future<void> show(BuildContext context, Track track) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet._(track: track),
    );
  }

  /// The sheet for anything without a card (album, playlist, artist, podcast):
  /// the Inzx link by default, or the YouTube Music one.
  static Future<void> showLinks(
    BuildContext context, {
    required String type,
    required String id,
    required String title,
    required String Function(String url) shareText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkSheet(
        type: type,
        id: id,
        title: title,
        shareText: shareText,
      ),
    );
  }

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  static const _native = NativeShare();
  static const _prefs = SharePreferences();
  static const _renderer = ShareCardRenderer();
  static const _maxLines = 4;

  ShareCardStyle _style = ShareCardStyle.dark;
  ShareCardMode _mode = ShareCardMode.song;
  int _theme = 0;

  ui.Image? _art;
  ui.Image? _logo;
  ShareCardPalette? _palette;

  /// Null on a build whose native side has no share bridge.
  Set<ShareApp>? _installed = const {};
  List<ShareApp> _apps = const [];

  List<LyricEntry> _lyrics = const [];
  final List<int> _picked = [];
  bool _lyricsLoading = true;

  /// The lyrics card shows the line being sung until a line is chosen by hand.
  bool _followPlayback = true;

  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;

  /// What's running, so a slow export can't be started twice.
  String? _busy;
  String? _status;
  Timer? _statusTimer;

  Track get _track => widget.track;

  bool get _isCurrent => ref.read(currentTrackProvider)?.id == _track.id;
  bool get _hasLink => !_track.id.startsWith('local_');

  @override
  void initState() {
    super.initState();
    unawaited(_loadChoices());
    unawaited(_loadArt());
    unawaited(_loadTargets());
    unawaited(_loadLyrics());
    // Live while the song is the one playing; the export freezes the moment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCurrent) return;
      final player = ref.read(audioPlayerServiceProvider);
      _setPosition(player.currentPosition);
      _positionSub = player.positionStream.listen(_setPosition);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _statusTimer?.cancel();
    _art?.dispose();
    _logo?.dispose();
    super.dispose();
  }

  void _setPosition(Duration position) {
    if (!mounted || !_isCurrent) return;
    if (position.inSeconds == _position.inSeconds) return;
    setState(() {
      _position = position;
      if (_followPlayback) _pickLineAt(position.inMilliseconds);
    });
  }

  Future<void> _loadChoices() async {
    final savedStyle = await _prefs.cardStyle();
    final savedTheme = await _prefs.cardTheme();
    if (!mounted) return;
    setState(() {
      _style = ShareCardStyle.values.firstWhere(
        (s) => s.name == savedStyle,
        orElse: () => ShareCardStyle.dark,
      );
      if (savedTheme != null &&
          savedTheme >= 0 &&
          savedTheme < ShareCardPalette.themeCount) {
        _theme = savedTheme;
      }
    });
  }

  Future<void> _loadTargets() async {
    final installed = await _native.installedApps();
    final recent = await _prefs.recentApps();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _apps = orderShareApps(recent: recent, installed: installed ?? const {});
    });
  }

  Future<void> _loadArt() async {
    final logo = await _decodeAsset('assets/logo_transparent.png', 256);
    if (mounted) {
      setState(() => _logo = logo);
    } else {
      logo?.dispose();
    }

    final bytes = await _artBytes();
    var palette = ShareCardPalette.fromAccent(
      ref.read(albumColorsProvider).accent,
    );
    ui.Image? art;
    if (bytes != null) {
      try {
        art = await _decode(bytes, 1024);
        final colors = await AlbumColorExtractor.extractFromBytes(bytes);
        palette = ShareCardPalette.fromAccent(colors.accent);
      } catch (e) {
        debugPrint('ShareSheet: could not read the cover: $e');
      }
    }
    if (!mounted) {
      art?.dispose();
      return;
    }
    setState(() {
      _art = art;
      _palette = palette;
    });
  }

  Future<Uint8List?> _artBytes() async {
    final local = _track.localFilePath;
    if (local != null && local.isNotEmpty) {
      final bytes = await LocalArtworkService.getArtworkBytes(
        local,
        track: _track,
      );
      if (bytes != null) return bytes;
    }
    for (final url in LocalArtworkService.artworkUrlCandidates(_track)) {
      try {
        final file = await DefaultCacheManager()
            .getSingleFile(url)
            .timeout(const Duration(seconds: 12));
        final bytes = await file.readAsBytes();
        if (MediaTagger.isImageBytes(bytes)) return bytes;
      } catch (e) {
        debugPrint('ShareSheet: no cover from $url: $e');
      }
    }
    return null;
  }

  static Future<ui.Image?> _decodeAsset(String asset, int width) async {
    try {
      final data = await rootBundle.load(asset);
      return await _decode(data.buffer.asUint8List(), width);
    } catch (e) {
      debugPrint('ShareSheet: could not load $asset: $e');
      return null;
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes, int width) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// Makes the line playing at [positionMs] the card's only line.
  void _pickLineAt(int positionMs) {
    if (_lyrics.isEmpty) return;
    final line = currentLineIndex(_lyrics, positionMs);
    _picked
      ..clear()
      ..add(line);
  }

  Future<void> _loadLyrics() async {
    final List<LyricEntry> lines;
    final state = ref.read(lyricsProvider);
    final result = state.videoId == _track.id ? state.currentLyrics : null;
    if (result != null && result.hasSyncedLyrics) {
      lines = [
        for (final line in result.lines!)
          if (line.text.trim().isNotEmpty)
            (text: line.text.trim(), timeMs: line.timeInMs),
      ];
    } else if (result != null && result.hasLyrics) {
      lines = lyricEntriesFrom(result.lyrics ?? '');
    } else {
      lines = await _cachedOrFetchedLyrics();
    }

    if (!mounted) return;
    setState(() {
      _lyrics = lines;
      _lyricsLoading = false;
      if (_followPlayback) {
        _pickLineAt(
          _isCurrent
              ? ref.read(audioPlayerServiceProvider).currentPosition.inMilliseconds
              : 0,
        );
      }
    });
  }

  Future<List<LyricEntry>> _cachedOrFetchedLyrics() async {
    try {
      List<LyricEntry> fromCache() {
        final cached = HiveService.lyricsBox.get(_track.id);
        final raw = cached?.syncedLyrics ?? cached?.plainLyrics;
        return raw == null ? const [] : lyricEntriesFrom(raw);
      }

      final cached = fromCache();
      if (cached.isNotEmpty) return cached;
      await LyricsWarmupService.instance.prefetchForTrack(
        videoId: _track.id,
        title: _track.title,
        artist: _track.artist,
        album: _track.album,
        durationSeconds: _track.duration.inSeconds,
        localFilePath: _track.localFilePath,
      );
      return fromCache();
    } catch (e) {
      debugPrint('ShareSheet: lyrics unavailable: $e');
      return const [];
    }
  }

  ShareCardData? _cardData() {
    final palette = _palette;
    if (palette == null) return null;
    final isCurrent = _isCurrent;
    final state = isCurrent ? ref.read(playbackStateProvider).valueOrNull : null;
    final duration = state?.duration ?? _track.duration;
    return ShareCardData(
      title: _track.title,
      artist: _track.artist,
      art: _art,
      logo: _logo,
      palette: palette,
      style: _style,
      mode: _mode,
      theme: _theme,
      barStyle: ref.read(progressBarStyleProvider),
      position: isCurrent ? _position : Duration.zero,
      duration: duration,
      isPlaying: state?.isPlaying ?? false,
      seed: _track.id.hashCode,
      lyrics: [for (final i in _picked.toList()..sort()) _lyrics[i].text],
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    );
  }

  String? get _inzxUrl =>
      _hasLink ? DeepLinkHandler.createShareUrl('song', _track.id) : null;

  String _text(String url) =>
      context.l10n.shareTrackText(_track.title, _track.artist, url);

  void _say(String message) {
    _statusTimer?.cancel();
    setState(() => _status = message);
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _status = null);
    });
  }

  /// Exports the card as it stands, then hands the file to [use].
  Future<void> _withCard(
    String task,
    Future<void> Function(String path) use,
  ) async {
    if (_busy != null) return;
    final data = _cardData();
    if (data == null) return;
    if (_mode == ShareCardMode.lyrics && data.lyrics.isEmpty) {
      _say(context.l10n.shareCardPickLyrics);
      return;
    }
    final failed = context.l10n.shareCardFailed;
    setState(() => _busy = task);
    try {
      final file = await _renderer.renderToFile(
        data,
        View.of(context),
        name: 'inzx_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await use(file.path);
    } catch (e) {
      debugPrint('ShareSheet: card export failed: $e');
      if (mounted) _say(failed);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    unawaited(_prefs.saveCardLook(_style.name, _theme));
  }

  Future<void> _sendTo(ShareApp app) => _withCard(app.wire, (path) async {
    final l10n = context.l10n;
    final url = _inzxUrl;
    final sent = await _native.sendTo(
      app,
      path,
      text: url == null ? null : _text(url),
    );
    if (!mounted) return;
    if (!sent) {
      _say(l10n.shareCardFailed);
      return;
    }
    await _prefs.markUsed(app);
    final recent = await _prefs.recentApps();
    if (!mounted) return;
    setState(() {
      _apps = orderShareApps(recent: recent, installed: _installed ?? const {});
    });
  });

  Future<void> _save() => _withCard('save', (path) async {
    final l10n = context.l10n;
    final saved = await _native.saveToGallery(
      path,
      'Inzx ${_track.title} ${DateTime.now().millisecondsSinceEpoch}.png'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' '),
    );
    if (mounted) _say(saved ? l10n.shareCardSaved : l10n.shareCardSaveFailed);
  });

  Future<void> _shareMore() async {
    if (_busy != null) return;
    final url = _inzxUrl;
    // Ready to paste straight away, whatever happens with the card.
    if (url != null) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) _say(context.l10n.shareCardLinkCopied);
    }
    if (!mounted) return;
    await _withCard('more', (path) async {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'image/png')],
          text: url == null ? null : _text(url),
        ),
      );
    });
  }

  void _shareYtLink() {
    final url = DeepLinkHandler.nativeYtMusicUrl('song', _track.id);
    if (url == null) return;
    unawaited(SharePlus.instance.share(ShareParams(text: _text(url))));
  }

  void _toggleLine(int index) {
    setState(() {
      _followPlayback = false;
      if (_picked.contains(index)) {
        if (_picked.length > 1) _picked.remove(index);
      } else if (_picked.length < _maxLines) {
        _picked.add(index);
      } else {
        _say(context.l10n.shareCardLyricsLimit);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The card's own inputs: watched so the preview follows them live.
    ref.watch(progressBarStyleProvider);
    ref.watch(playbackStateProvider);
    final l10n = context.l10n;
    final palette =
        _palette ??
        ShareCardPalette.fromAccent(ref.watch(albumColorsProvider).accent);
    final data = _cardData();
    final hasNative = _installed != null;
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      child: Material(
        color: palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, media.padding.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.share,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${_track.title} · ${_track.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Segments<ShareCardStyle>(
                    value: _style,
                    palette: palette,
                    compact: true,
                    options: {
                      ShareCardStyle.dark: l10n.shareCardStyleDark,
                      ShareCardStyle.liquid: l10n.shareCardStyleLiquid,
                      ShareCardStyle.light: l10n.shareCardStyleLight,
                    },
                    onChanged: (v) => setState(() => _style = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Segments<ShareCardMode>(
                value: _mode,
                palette: palette,
                expand: true,
                options: {
                  ShareCardMode.song: l10n.shareCardSong,
                  ShareCardMode.lyrics: l10n.shareCardLyrics,
                },
                onChanged: (v) => setState(() => _mode = v),
              ),
              const SizedBox(height: 12),
              FractionallySizedBox(
                widthFactor: 0.62,
                child: AspectRatio(
                  aspectRatio:
                      kShareCardSize.width / kShareCardSize.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: data == null
                        ? ColoredBox(
                            color: palette.raised,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.tint,
                              ),
                            ),
                          )
                        : FittedBox(
                            child: RepaintBoundary(
                              child: ShareCard(data: data),
                            ),
                          ),
                  ),
                ),
              ),
              if (_mode == ShareCardMode.lyrics) ...[
                const SizedBox(height: 10),
                _LyricPicker(
                  lines: [for (final line in _lyrics) line.text],
                  picked: _picked,
                  followLine: _followPlayback && _picked.isNotEmpty
                      ? _picked.first
                      : null,
                  loading: _lyricsLoading,
                  palette: palette,
                  onToggle: _toggleLine,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.shareCardTheme,
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < ShareCardPalette.themeCount; i++)
                    _ThemeDot(
                      art: _art,
                      gradient: palette.backdrop(i),
                      selected: i == _theme,
                      ring: palette.tint,
                      onTap: () => setState(() => _theme = i),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final app in _apps)
                    _Target(
                      label: app == ShareApp.instagram
                          ? l10n.shareCardInstagram
                          : l10n.shareCardSnapchat,
                      background: app == ShareApp.instagram
                          ? const LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [
                                Color(0xFFF9A13C),
                                Color(0xFFE1306C),
                                Color(0xFF8A3AB9),
                              ],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFFFFC00), Color(0xFFFFFC00)],
                            ),
                      iconColor: app == ShareApp.instagram
                          ? Colors.white
                          : const Color(0xFF111111),
                      glyph: app == ShareApp.instagram
                          ? _InstagramGlyph(Colors.white)
                          : _SnapchatGlyph(const Color(0xFF111111)),
                      busy: _busy == app.wire,
                      onTap: () => _sendTo(app),
                    ),
                  if (hasNative)
                    _Target(
                      label: l10n.shareCardSave,
                      background: LinearGradient(
                        colors: [palette.accent, palette.accent],
                      ),
                      iconColor: palette.onAccent,
                      icon: Icons.download_rounded,
                      busy: _busy == 'save',
                      onTap: _save,
                    ),
                  if (_hasLink)
                    _Target(
                      label: l10n.shareCardYtMusicLink,
                      background: const LinearGradient(
                        colors: [Color(0xFFFF0033), Color(0xFFFF0033)],
                      ),
                      iconColor: Colors.white,
                      icon: Icons.play_circle_outline_rounded,
                      onTap: _shareYtLink,
                    ),
                  _Target(
                    label: l10n.shareCardMore,
                    background: LinearGradient(
                      colors: [palette.raised, palette.raised],
                    ),
                    iconColor: Colors.white,
                    icon: Icons.share_rounded,
                    busy: _busy == 'more',
                    onTap: _shareMore,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 18,
                child: Text(
                  _status ?? '',
                  style: TextStyle(fontSize: 12, color: palette.tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.palette,
    this.compact = false,
    this.expand = false,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final ShareCardPalette palette;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    Widget option(T key, String label) {
      final selected = key == value;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 6 : 9,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 12 : 13.5,
                fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
                color: selected ? palette.onTint : Colors.white60,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final entry in options.entries)
            expand
                ? Expanded(child: option(entry.key, entry.value))
                : option(entry.key, entry.value),
        ],
      ),
    );
  }
}

class _LyricPicker extends StatefulWidget {
  const _LyricPicker({
    required this.lines,
    required this.picked,
    required this.followLine,
    required this.loading,
    required this.palette,
    required this.onToggle,
  });

  final List<String> lines;
  final List<int> picked;

  /// The line playback is on, while the card is following it.
  final int? followLine;
  final bool loading;
  final ShareCardPalette palette;
  final ValueChanged<int> onToggle;

  @override
  State<_LyricPicker> createState() => _LyricPickerState();
}

class _LyricPickerState extends State<_LyricPicker> {
  // Rows are usually one line tall, which is close enough to keep the current
  // line in view; one row above it stays visible for context.
  static const double _rowExtent = 42;

  final ScrollController _controller = ScrollController();

  double _offsetFor(int line) => (line - 1) * _rowExtent;

  void _showLine(int? line, {required bool animate}) {
    if (line == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target = _offsetFor(
        line,
      ).clamp(0.0, _controller.position.maxScrollExtent);
      if (animate) {
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _controller.jumpTo(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _showLine(widget.followLine, animate: false);
  }

  @override
  void didUpdateWidget(covariant _LyricPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading && !widget.loading) {
      _showLine(widget.followLine, animate: false);
    } else if (widget.followLine != oldWidget.followLine) {
      _showLine(widget.followLine, animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lines = widget.lines;
    if (widget.loading || lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: widget.loading
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.tint,
                ),
              )
            : Text(
                context.l10n.shareCardNoLyrics,
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
      );
    }
    return SizedBox(
      height: 168,
      child: ListView.separated(
        controller: _controller,
        itemCount: lines.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final selected = widget.picked.contains(i);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onToggle(i),
            child: Container(
              alignment: Alignment.centerLeft,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? palette.tint : palette.raised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                lines[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? palette.onTint : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({
    required this.art,
    required this.gradient,
    required this.selected,
    required this.ring,
    required this.onTap,
  });

  final ui.Image? art;
  final Gradient? gradient;
  final bool selected;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = art;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? ring : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipOval(
            child: gradient != null || image == null
                ? DecoratedBox(decoration: BoxDecoration(gradient: gradient))
                : RawImage(image: image, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.icon,
    this.glyph,
    this.busy = false,
  });

  final String label;
  final Gradient background;
  final Color iconColor;
  final VoidCallback onTap;
  final IconData? icon;
  final _Glyph? glyph;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final glyph = this.glyph;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: iconColor,
                        ),
                      )
                    : glyph != null
                    ? CustomPaint(
                        size: const Size.square(24),
                        painter: glyph,
                      )
                    : Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icons with no Material or Iconsax equivalent, drawn on a 24-unit grid.
abstract class _Glyph extends CustomPainter {
  _Glyph(this.color);

  final Color color;

  void draw(Canvas canvas, Paint paint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    draw(canvas, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Glyph oldDelegate) => oldDelegate.color != color;
}

class _InstagramGlyph extends _Glyph {
  _InstagramGlyph(super.color);

  @override
  void draw(Canvas canvas, Paint paint) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(4, 4, 20, 20, const Radius.circular(4.5)),
        paint,
      )
      ..drawCircle(const Offset(12, 12), 3.6, paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(16.8, 7.2), 0.95, paint);
  }
}

class _SnapchatGlyph extends _Glyph {
  _SnapchatGlyph(super.color);

  static final Path _ghost = Path()
    ..moveTo(12, 3)
    ..cubicTo(8.8, 3, 6.8, 5.4, 6.8, 8.4)
    ..lineTo(6.8, 10.6)
    ..cubicTo(6.3, 10.8, 5.8, 10.7, 5.3, 10.6)
    ..cubicTo(4.7, 10.5, 4.4, 11.3, 5, 11.6)
    ..cubicTo(5.6, 12, 6.6, 12.3, 7, 12.8)
    ..cubicTo(6.5, 14.5, 5, 15.8, 3.3, 16.4)
    ..cubicTo(2.8, 16.6, 2.9, 17.2, 3.4, 17.4)
    ..cubicTo(4.1, 17.6, 4.8, 17.7, 5.4, 17.9)
    ..cubicTo(5.7, 18.6, 5.7, 19.1, 6.4, 18.9)
    ..cubicTo(7.7, 18.6, 8.9, 18.7, 10.1, 19.6)
    ..cubicTo(10.7, 20, 11.3, 20.3, 12, 20.3)
    ..cubicTo(12.7, 20.3, 13.3, 20, 13.9, 19.6)
    ..cubicTo(15.1, 18.7, 16.3, 18.6, 17.6, 18.9)
    ..cubicTo(18.3, 19.1, 18.3, 18.6, 18.6, 17.9)
    ..cubicTo(19.2, 17.7, 19.9, 17.6, 20.6, 17.4)
    ..cubicTo(21.1, 17.2, 21.2, 16.6, 20.7, 16.4)
    ..cubicTo(19, 15.8, 17.5, 14.5, 17, 12.8)
    ..cubicTo(17.4, 12.3, 18.4, 12, 19, 11.6)
    ..cubicTo(19.6, 11.3, 19.3, 10.5, 18.7, 10.6)
    ..cubicTo(18.2, 10.7, 17.7, 10.8, 17.2, 10.6)
    ..lineTo(17.2, 8.4)
    ..cubicTo(17.2, 5.4, 15.2, 3, 12, 3)
    ..close();

  @override
  void draw(Canvas canvas, Paint paint) {
    canvas.drawPath(_ghost, paint);
  }
}

class _LinkSheet extends StatelessWidget {
  const _LinkSheet({
    required this.type,
    required this.id,
    required this.title,
    required this.shareText,
  });

  final String type;
  final String id;
  final String title;
  final String Function(String url) shareText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final palette = ShareCardPalette.fromAccent(scheme.primary);
    final ytUrl = DeepLinkHandler.nativeYtMusicUrl(type, id);
    final inzxUrl = DeepLinkHandler.createShareUrl(type, id);

    void share(String url) {
      Navigator.pop(context);
      unawaited(SharePlus.instance.share(ShareParams(text: shareText(url))));
    }

    return Material(
      color: palette.sheet,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.share,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Target(
                  label: l10n.shareCardMore,
                  background: LinearGradient(
                    colors: [palette.accent, palette.accent],
                  ),
                  iconColor: palette.onAccent,
                  icon: Icons.share_rounded,
                  onTap: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: inzxUrl)),
                    );
                    share(inzxUrl);
                  },
                ),
                if (ytUrl != null)
                  _Target(
                    label: l10n.shareCardYtMusicLink,
                    background: const LinearGradient(
                      colors: [Color(0xFFFF0033), Color(0xFFFF0033)],
                    ),
                    iconColor: Colors.white,
                    icon: Icons.play_circle_outline_rounded,
                    onTap: () => share(ytUrl),
                  ),
                const Spacer(),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
