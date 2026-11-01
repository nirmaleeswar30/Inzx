import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../providers/repository_providers.dart';
import '../services/ytmusic_sync_service.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../../core/providers/theme_provider.dart';
import '../../main.dart';
import 'ytmusic_login_screen.dart';
import 'audio_settings_screen.dart';
import 'player_appearance_screen.dart';
import 'download_settings_screen.dart';
import 'backup_restore_screen.dart';
import 'logs_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/github_release_update_service.dart';
import '../services/shorebird_update_service.dart';
import 'widgets/whats_new_dialog.dart';
import 'widgets/color_picker_dialog.dart';
import '../services/discord/discord_rpc_service.dart';
import 'discord_rich_presence_screen.dart';
import 'widgets/discord_logo.dart';
import 'widgets/ai_lyrics_settings_sheet.dart';
import 'scrobbling_screen.dart';
import 'equalizer_screen.dart';
import '../services/scrobbling/scrobble_service.dart';

/// Provider for sync service
final ytMusicSyncServiceProvider = Provider<YTMusicSyncService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return YTMusicSyncService(innerTube);
});

/// YT Music account & settings screen — redesigned with dynamic theming
class YTMusicSettingsScreen extends ConsumerStatefulWidget {
  const YTMusicSettingsScreen({super.key});

  @override
  ConsumerState<YTMusicSettingsScreen> createState() =>
      _YTMusicSettingsScreenState();
}

class _YTMusicSettingsScreenState extends ConsumerState<YTMusicSettingsScreen> {
  bool _isSyncing = false;
  SyncResult? _lastSyncResult;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────

  ColorScheme get _colors => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // Dynamic colors from album art
  AlbumColors get _albumColors => ref.watch(albumColorsProvider);
  bool get _hasAlbumColors => !_albumColors.isDefault;

  /// Background color - plain white in light mode, album colors in dark mode
  Color get _backgroundColor {
    if (_hasAlbumColors && _isDark) {
      return _albumColors.backgroundSecondary;
    }
    return _isDark ? InzxColors.darkBackground : InzxColors.background;
  }

  /// Accent color (dynamic or theme default)
  Color get _accentColor =>
      _hasAlbumColors ? _albumColors.accent : _colors.primary;

  Color get _cardColor => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.white.withValues(alpha: 0.85);
  Color get _textPrimary =>
      _isDark ? InzxColors.darkTextPrimary : InzxColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? InzxColors.darkTextSecondary : InzxColors.textSecondary;
  Color get _textTertiary =>
      _isDark ? InzxColors.darkTextTertiary : InzxColors.textTertiary;

  /// Searchable items from nested screens (Audio, Downloads, Backup, Appearance)
  /// and direct quick actions on the main settings screen.
  List<_SearchableItem> get _deepSearchItems {
    final l10n = context.l10n;
    return [
      // ── Audio Settings Screen ───────────────────────────────────────────
      _SearchableItem(
        tags: [
          'streaming',
          'quality',
          'audio',
          'bitrate',
          'kbps',
          'auto',
          'low',
          'medium',
          'high',
          'max',
          'sound',
        ],
        title: l10n.streamingQuality,
        subtitle: l10n.streamingQualitySubtitle,
        icon: Iconsax.volume_high,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'jiosaavn',
          'saavn',
          '320kbps',
          'high quality',
          'studio',
          'studio quality',
          'external sources',
          'hd audio',
          'lossless',
          'aac',
          'stream',
          'sources',
        ],
        title: 'High Quality Sources (JioSaavn 320kbps)',
        subtitle:
            'Enable external studio-quality 320kbps streams for matching tracks',
        icon: Iconsax.music_dashboard,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'crossfade',
          'transition',
          'blend',
          'gapless',
          'playback',
          'duration',
          'overlap',
          'fade',
        ],
        title: l10n.crossfadeTransition,
        subtitle: l10n.crossfadeTransitionSubtitle,
        icon: Iconsax.blend,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'streaming cache',
          'cache',
          'buffer',
          'preload',
          'wifi only',
          'wifi',
          'limit',
          'max concurrent',
          'pre-cache',
          'data saver',
        ],
        title: l10n.streamingCache,
        subtitle: l10n.streamingCacheSubtitle,
        icon: Iconsax.cpu,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'prefer audio versions',
          'audio version',
          'skip music video',
          'official audio',
          'video',
          'music video',
        ],
        title: l10n.preferAudioVersions,
        subtitle: l10n.preferAudioVersionsSubtitle,
        icon: Iconsax.music,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'smart audio routing',
          'audio output',
          'output device',
          'bluetooth',
          'speaker',
          'headphone',
          'routing',
        ],
        title: l10n.smartAudioRouting,
        subtitle: l10n.smartAudioRoutingSubtitle,
        icon: Iconsax.volume_high,
        screen: const AudioSettingsScreen(),
      ),

      // ── Download Settings Screen ────────────────────────────────────────
      _SearchableItem(
        tags: [
          'download',
          'quality',
          'offline',
          'bitrate',
          'audio quality',
          'kbps',
          'save',
        ],
        title: l10n.downloadQuality,
        subtitle: l10n.downloadQualitySubtitle,
        icon: Iconsax.document_download,
        screen: const DownloadSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'download',
          'location',
          'path',
          'folder',
          'storage',
          'directory',
          'save to',
          'internal storage',
          'sd card',
        ],
        title: l10n.downloadLocation,
        subtitle: l10n.downloadLocationSubtitle,
        icon: Iconsax.folder_2,
        screen: const DownloadSettingsScreen(),
      ),
      _SearchableItem(
        tags: [
          'data',
          'usage',
          'network',
          'bandwidth',
          'mobile',
          'storage info',
          'disk space',
          'mb',
          'megabytes',
        ],
        title: l10n.dataUsageInfo,
        subtitle: l10n.dataUsageInfoSubtitle,
        icon: Iconsax.chart_1,
        screen: const DownloadSettingsScreen(),
      ),

      // ── Backup & Restore Screen ─────────────────────────────────────────
      _SearchableItem(
        tags: [
          'backup',
          'export',
          'save',
          'file',
          'json',
          'export playlists',
          'data export',
        ],
        title: l10n.createBackup,
        subtitle: l10n.createBackupSubtitle,
        icon: Iconsax.export_1,
        screen: const BackupRestoreScreen(),
      ),
      _SearchableItem(
        tags: [
          'restore',
          'import',
          'load',
          'file',
          'recover data',
          'import playlists',
        ],
        title: l10n.restoreBackup,
        subtitle: l10n.restoreBackupSubtitle,
        icon: Iconsax.import_1,
        screen: const BackupRestoreScreen(),
      ),

      // ── Player & Now Playing Appearance Screen ──────────────────────────
      _SearchableItem(
        tags: [
          'now playing style',
          'player',
          'ripple',
          'cinematic',
          'edge',
          'layout',
          'full player',
          'ui',
        ],
        title: l10n.nowPlayingStyle,
        subtitle: getNowPlayingStyleName(ref.watch(nowPlayingStyleProvider)),
        icon: Icons.art_track_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'progress bar',
          'waveform',
          'audio waveform',
          'scrubber',
          'spectrum',
          'seek',
          'seekbar',
          'slider',
        ],
        title: l10n.progressBarStyle,
        subtitle: getProgressBarStyleName(ref.watch(progressBarStyleProvider)),
        icon: Icons.graphic_eq_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'liquid glass',
          'glass',
          'navbar',
          'nav',
          'blur',
          'floating navbar',
          'frosted',
          'translucent',
        ],
        title: l10n.liquidGlass,
        subtitle: l10n.liquidGlassSubtitle,
        icon: Icons.water_drop_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'rotating miniplayer art',
          'rotating album art',
          'spin',
          'vinyl',
          'disc',
          'record player',
          'miniplayer',
          'rotate',
        ],
        title: l10n.rotatingMiniplayerArt,
        subtitle: l10n.rotatingMiniplayerArtSubtitle,
        icon: Icons.album_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'animated album art',
          'canvas',
          'motion',
          'rotate',
          'moving art',
          'canvas video',
          'animation',
        ],
        title: l10n.animatedAlbumArt,
        subtitle: l10n.animatedAlbumArtSubtitle,
        icon: Icons.play_circle_outline_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'ambient reflection canvas',
          'ambient reflection',
          'cinematic ambient',
          'glow',
          'glow reflection',
          'background glow',
        ],
        title: l10n.ambientReflectionCanvasTitle,
        subtitle: l10n.ambientReflectionCanvasSubtitle,
        icon: Icons.blur_on_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'dynamic ambient canvas',
          'dynamic ambient',
          'pulsing glow',
          'live glow',
          'ambient light',
          'lighting',
        ],
        title: l10n.dynamicAmbientCanvasTitle,
        subtitle: l10n.dynamicAmbientCanvasSubtitle,
        icon: Icons.lightbulb_outline_rounded,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'lyrics',
          'lyrics below album art',
          'now playing lyrics',
          'embedded lyrics',
          'text',
        ],
        title: l10n.lyricsBelowAlbumArt,
        subtitle: l10n.lyricsBelowAlbumArtSubtitle,
        icon: Iconsax.text,
        screen: const PlayerAppearanceScreen(),
      ),
      _SearchableItem(
        tags: [
          'ai lyrics translation',
          'ai lyrics',
          'lyrics translation',
          'translation',
          'translate',
          'transliterate',
          'pronunciation',
          'furigana',
          'romaji',
          'transliteration',
          'romanization',
          'gemini',
          'openai',
          'deepseek',
          'japanese',
          'korean',
          'chinese',
        ],
        title: l10n.aiLyricsTranslation,
        subtitle: l10n.aiLyricsTranslationSubtitle,
        icon: Iconsax.translate,
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const AiLyricsSettingsSheet(),
          );
        },
      ),

      // ── Discord Rich Presence Screen ──────────────────────────────────
      _SearchableItem(
        tags: [
          'discord',
          'rich presence',
          'rpc',
          'status',
          'presence',
          'social',
          'listening activity',
          'game activity',
        ],
        title: 'Discord Rich Presence',
        subtitle: 'Show your listening activity on Discord',
        icon: Iconsax.game,
        screen: const DiscordRichPresenceScreen(),
      ),

      // ── Scrobbling ────────────────────────────────────────────────────
      _SearchableItem(
        tags: ['scrobble', 'scrobbling', 'last.fm', 'lastfm', 'listenbrainz', 'libre.fm'],
        title: 'Scrobbling',
        subtitle: 'Last.fm and ListenBrainz',
        icon: Iconsax.radar,
        screen: const ScrobblingScreen(),
      ),

      // ── Equalizer ─────────────────────────────────────────────────────
      _SearchableItem(
        tags: ['equalizer', 'equaliser', 'eq', 'bass', 'treble', 'preset'],
        title: 'Equalizer',
        subtitle: '7 bands with presets',
        icon: Iconsax.setting_4,
        screen: const EqualizerScreen(),
      ),

      // ── App Logs & Diagnostics Screen ─────────────────────────────────
      _SearchableItem(
        tags: [
          'app logs',
          'logs',
          'diagnostics',
          'crash diagnostics',
          'crash',
          'error',
          'debug',
          'traces',
          'stack trace',
          'export logs',
        ],
        title: 'App Logs & Diagnostics',
        subtitle: 'View, copy & export crash traces',
        icon: Iconsax.document_code,
        screen: const AppLogsScreen(),
      ),

      // ── Direct Settings Actions ───────────────────────────────────────
      _SearchableItem(
        tags: [
          'language',
          'app language',
          'locale',
          'translate ui',
          'idioma',
          'lang',
        ],
        title: l10n.language,
        subtitle: _languageLabel(ref.watch(appLocaleProvider)),
        icon: Iconsax.language_square,
        onTap: _showLanguageSelector,
      ),
      _SearchableItem(
        tags: [
          'content location',
          'country',
          'region',
          'recommendations location',
          'trending country',
        ],
        title: l10n.contentLocation,
        subtitle: _contentLocationLabel(ref.watch(appContentCountryProvider)),
        icon: Icons.public_rounded,
        onTap: _showContentLocationSelector,
      ),
      _SearchableItem(
        tags: [
          'accent color',
          'custom color',
          'color wheel',
          'theme color',
          'palette',
          'custom accent',
          'hex color',
        ],
        title: l10n.customColorWheel,
        subtitle: 'Customize the app accent color with a precision color wheel',
        icon: Iconsax.colorfilter,
        onTap: () => _openCustomColorPicker(ref.read(customAccentColorProvider)),
      ),
      _SearchableItem(
        tags: [
          'theme',
          'theme mode',
          'dark mode',
          'light mode',
          'system theme',
          'auto theme',
          'night mode',
        ],
        title: l10n.theme,
        subtitle: ref.watch(themeModeProvider) == InzxThemeMode.system
            ? l10n.themeAuto
            : ref.watch(themeModeProvider) == InzxThemeMode.light
            ? l10n.themeLight
            : l10n.themeDark,
        icon: Iconsax.moon,
        onTap: () {
          final nextMode = ref.read(themeModeProvider) == InzxThemeMode.dark
              ? InzxThemeMode.light
              : ref.read(themeModeProvider) == InzxThemeMode.light
              ? InzxThemeMode.system
              : InzxThemeMode.dark;
          ref.read(themeModeProvider.notifier).setThemeMode(nextMode);
        },
      ),
      _SearchableItem(
        tags: [
          'stats for nerds',
          'nerd stats',
          'audio stats',
          'debug stats',
          'technical info',
        ],
        title: l10n.statsForNerds,
        subtitle: ref.watch(showNerdStatsProvider) ? 'Enabled' : 'Disabled',
        icon: Iconsax.status,
        onTap: () {
          final current = ref.read(showNerdStatsProvider);
          ref.read(audioPlayerServiceProvider).setShowNerdStats(!current);
        },
      ),
      _SearchableItem(
        tags: [
          'share links',
          'share youtube music links',
          'share',
          'native links',
          'youtube music link format',
        ],
        title: l10n.shareYoutubeMusicLinks,
        subtitle: ref.watch(shareNativeLinksProvider)
            ? 'Sharing YouTube Music links'
            : 'Sharing standard YouTube links',
        icon: Iconsax.share,
        onTap: () {
          final current = ref.read(shareNativeLinksProvider);
          ref.read(shareNativeLinksProvider.notifier).setEnabled(!current);
        },
      ),
      _SearchableItem(
        tags: [
          'check for updates',
          'update',
          'ota',
          'patch',
          'github update',
          'new version',
          'shorebird',
        ],
        title: 'Check for App Updates',
        subtitle: 'Check GitHub & OTA for new versions and updates',
        icon: Iconsax.refresh_circle,
        onTap: _handleCheckForUpdates,
      ),
      _SearchableItem(
        tags: [
          'what\'s new',
          'changelog',
          'release notes',
          'features',
          'new features',
          'version notes',
        ],
        title: 'What\'s New',
        subtitle: 'View release notes, changelogs & new features',
        icon: Iconsax.document_text,
        onTap: () => WhatsNewDialog.show(context),
      ),
      _SearchableItem(
        tags: [
          'version details',
          'app info',
          'version',
          'build number',
          'credits',
          'about inzx',
        ],
        title: 'Version Details',
        subtitle: 'App logo, version, patch number & credits',
        icon: Iconsax.device_message,
        onTap: _showAppInfoPopup,
      ),
      _SearchableItem(
        tags: [
          'sponsor',
          'support',
          'donate',
          'upi',
          'github sponsors',
          'contribute',
        ],
        title: 'Sponsor Inzx',
        subtitle: 'Support the development via GitHub Sponsors or UPI',
        icon: Iconsax.heart5,
        onTap: _showSupportSheet,
      ),
      _SearchableItem(
        tags: [
          'cleanup cache',
          'clear cache',
          'clean cache',
          'free up space',
          'storage cleanup',
          'disk cache',
        ],
        title: l10n.cleanUp,
        subtitle: l10n.clearCache,
        icon: Iconsax.refresh,
        onTap: () async {
          final cacheManager = ref.read(cacheManagementProvider);
          await cacheManager.cleanupExpiredCache();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l10n.cacheCleanupComplete,
                  style: TextStyle(color: _colors.onInverseSurface),
                ),
                backgroundColor: _colors.inverseSurface,
              ),
            );
            setState(() {});
          }
        },
      ),
      _SearchableItem(
        tags: [
          'sync',
          'sync now',
          'sync library',
          'refresh library',
          'refresh playlists',
          'sync liked songs',
        ],
        title: l10n.syncNow,
        subtitle: _isSyncing
            ? l10n.syncing
            : 'Sync liked songs, albums & playlists',
        icon: Iconsax.refresh_2,
        onTap: _sync,
      ),
    ];
  }

  // ── build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(ytMusicAuthStateProvider);
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: authState.isLoading
          ? Center(child: CircularProgressIndicator(color: _accentColor))
          : CustomScrollView(
              slivers: [
                // ── Collapsing App Bar ───────────────────────────────
                SliverAppBar.large(
                  expandedHeight: 120,
                  backgroundColor: _backgroundColor,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Iconsax.arrow_left, color: _textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(color: _backgroundColor),
                    title: Text(
                      l10n.settings,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    titlePadding: const EdgeInsetsDirectional.only(
                      start: 56,
                      bottom: 16,
                    ),
                  ),
                ),

                // ── Search bar ───────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(child: _buildSearchBar()),
                ),

                // ── Body ─────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.list(
                    children: [
                      const SizedBox(height: 12),
                      if (authState.isLoggedIn)
                        ..._filteredSections(_loggedInSections(authState))
                      else
                        ..._filteredSections(_loggedOutSections()),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Search ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: _isDark
            ? Colors.white.withValues(alpha: 0.06)
            : _colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDark
              ? InzxColors.darkBorder
              : InzxColors.border.withValues(alpha: 0.4),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase()),
        style: TextStyle(fontSize: 14, color: _textPrimary),
        decoration: InputDecoration(
          hintText: context.l10n.searchSettingsHint,
          hintStyle: TextStyle(fontSize: 14, color: _textTertiary),
          prefixIcon: Icon(
            Iconsax.search_normal,
            size: 18,
            color: _textTertiary,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: _textTertiary,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  /// Filter sections based on search query
  /// Each entry is a (tag, widget) pair; tags are keywords for filtering
  List<Widget> _filteredSections(List<_TaggedSection> tagged) {
    if (_searchQuery.isEmpty) {
      final widgets = <Widget>[];
      for (final t in tagged) {
        widgets.add(t.widget);
        widgets.add(const SizedBox(height: 20));
      }
      if (widgets.isNotEmpty) widgets.removeLast();
      return widgets;
    }

    // Search through main sections
    final matchedSections = tagged
        .where((t) => _matchesSearchQuery(t.tags))
        .toList();

    // Search through deep-link items (Audio, Downloads, Backup settings)
    final matchedItems = _deepSearchItems
        .where((item) => _matchesSearchQuery(item.searchTerms))
        .toList();

    if (matchedSections.isEmpty && matchedItems.isEmpty) {
      return [
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(Iconsax.search_normal, size: 40, color: _textTertiary),
              const SizedBox(height: 12),
              Text(
                context.l10n.noMatchingSettings,
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ];
    }

    final widgets = <Widget>[];

    // Add matched deep-link items first (more specific results)
    if (matchedItems.isNotEmpty) {
      widgets.add(_buildSearchResultsCard(matchedItems));
      if (matchedSections.isNotEmpty) widgets.add(const SizedBox(height: 20));
    }

    // Add matched main sections
    for (final t in matchedSections) {
      widgets.add(t.widget);
      widgets.add(const SizedBox(height: 20));
    }
    if (widgets.isNotEmpty && widgets.last is SizedBox) widgets.removeLast();
    return widgets;
  }

  bool _matchesSearchQuery(Iterable<String> values) {
    return values.any((value) => value.toLowerCase().contains(_searchQuery));
  }

  /// Build a card showing search results from nested screens
  Widget _buildSearchResultsCard(List<_SearchableItem> items) {
    return _sectionCard(
      children: [
        _sectionHeader(context.l10n.foundInSettings, Iconsax.search_status),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Column(
            children: [
              _settingsTile(
                icon: item.icon,
                iconBg: _accentColor.withValues(alpha: 0.8),
                title: item.title,
                subtitle: item.subtitle,
                onTap: () {
                  _searchFocusNode.unfocus();
                  if (item.onTap != null) {
                    item.onTap!();
                  } else if (item.screen != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => item.screen!),
                    );
                  }
                },
              ),
              if (index < items.length - 1)
                Divider(
                  height: 1,
                  color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
                ),
            ],
          );
        }),
      ],
    );
  }

  // ── Section lists ──────────────────────────────────────────────────

  /// Shared search tags for the Appearance section so logged-in and logged-out
  /// stay in sync and every appearance option is discoverable via search.
  List<String> get _appearanceTags => [
    context.l10n.appearance,
    context.l10n.theme,
    context.l10n.language,
    context.l10n.contentLocation,
    context.l10n.dynamicColorsNote,
    context.l10n.accentColor,
    context.l10n.statsForNerds,
    'appearance',
    'theme',
    'dark',
    'dark mode',
    'light',
    'light mode',
    'mode',
    'system',
    'auto',
    'accent color',
    'color',
    'custom color',
    'color wheel',
    'palette',
    // Player & Now Playing sub-screen (discoverable from Appearance)
    'player',
    'now playing',
    'now playing style',
    'progress bar',
    'waveform',
    'liquid glass',
    'rotating miniplayer art',
    'animated album art',
    'ambient reflection',
    'dynamic ambient',
    'lyrics',
    'ai lyrics',
    'stats for nerds',
    'nerd stats',
    'content location',
    'region',
    'country',
    'language',
    'locale',
  ];

  List<_TaggedSection> _loggedOutSections() => [
    _TaggedSection([
      context.l10n.yourProfile,
      context.l10n.signInWithGoogle,
      context.l10n.connectYoutubeMusic,
      context.l10n.connectYoutubeMusicSubtitle,
      'profile',
      'google',
      'youtube',
      'yt music',
      'connect',
      'account',
      'sign in',
      'login',
      'auth',
      'jams',
    ], _buildYTMusicConnectCard()),
    _TaggedSection(_appearanceTags, _buildAppearanceSection()),
    _TaggedSection([
      context.l10n.quickActions,
      context.l10n.audio,
      context.l10n.downloads,
      context.l10n.backupRestore,
      context.l10n.streamingQuality,
      context.l10n.downloadQuality,
      'audio',
      'streaming',
      'quality',
      'crossfade',
      'cache',
      'jiosaavn',
      '320kbps',
      'download',
      'download location',
      'backup',
      'restore',
      'discord',
      'rpc',
    ], _buildQuickActions()),
    _TaggedSection([
      context.l10n.appInfo,
      context.l10n.settings,
      context.l10n.shareYoutubeMusicLinks,
      'app',
      'info',
      'ota',
      'patch',
      'version',
      'update',
      'check for updates',
      'what\'s new',
      'changelog',
      'logs',
      'crash diagnostics',
      'sponsor',
      'donate',
      'share',
      'youtube music links',
      'native links',
    ], _buildOtaDebugSection()),
  ];

  List<_TaggedSection> _loggedInSections(YTMusicAuthState authState) => [
    _TaggedSection([
      context.l10n.yourProfile,
      context.l10n.signInWithGoogle,
      context.l10n.googleUser,
      context.l10n.connected,
      context.l10n.youtubeMusicLabel,
      'profile',
      'google',
      'account',
      'sign in',
      'youtube',
      'yt music',
      'connected',
      'auth',
    ], _buildAccountSection(authState)),
    _TaggedSection(_appearanceTags, _buildAppearanceSection()),
    _TaggedSection([
      context.l10n.quickActions,
      context.l10n.audio,
      context.l10n.downloads,
      context.l10n.backupRestore,
      context.l10n.streamingQuality,
      context.l10n.downloadQuality,
      context.l10n.restoreBackup,
      'audio',
      'streaming',
      'quality',
      'crossfade',
      'download',
      'download location',
      'backup',
      'restore',
      'jiosaavn',
      '320kbps',
      'discord',
      'rpc',
    ], _buildQuickActions()),
    _TaggedSection([
      context.l10n.sync,
      context.l10n.syncNow,
      context.l10n.library,
      'sync',
      'refresh',
      'library',
      'sync now',
      'sync library',
    ], _buildSyncSection()),
    _TaggedSection([
      context.l10n.library,
      context.l10n.likedSongsLabel,
      context.l10n.albums,
      context.l10n.playlists,
      context.l10n.artists,
      'library',
      'liked',
      'albums',
      'playlists',
      'artists',
      'stats',
      'saved songs',
    ], _buildLibraryStats()),
    _TaggedSection([
      context.l10n.streamingCache,
      context.l10n.cleanUp,
      context.l10n.clearCache,
      'cache',
      'storage',
      'cleanup',
      'clear',
      'clear cache',
      'clean up',
      'free up space',
      'disk space',
    ], _buildCacheSection()),
    _TaggedSection([
      context.l10n.analytics,
      'analytics',
      'hits',
      'misses',
      'network',
      'stats',
      'bandwidth',
      'cache analytics',
    ], _buildAnalyticsSection()),
    _TaggedSection([
      context.l10n.appInfo,
      context.l10n.settings,
      context.l10n.shareYoutubeMusicLinks,
      'app',
      'info',
      'ota',
      'patch',
      'version',
      'update',
      'check for updates',
      'what\'s new',
      'changelog',
      'logs',
      'crash diagnostics',
      'sponsor',
      'donate',
      'share',
      'youtube music links',
      'native links',
    ], _buildOtaDebugSection()),
    _TaggedSection([
      context.l10n.signOut,
      'logout',
      'disconnect',
      'sign out',
    ], _buildLogoutButton()),
  ];

  // ── Reusable card container ────────────────────────────────────────

  Widget _sectionCard({required List<Widget> children}) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isDark
                ? InzxColors.darkBorder
                : (_hasAlbumColors
                      ? _accentColor.withValues(alpha: 0.15)
                      : InzxColors.border.withValues(alpha: 0.3)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _accentColor),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // ── YT Music Connect (logged-out) ─────────────────────────────────

  Widget _buildYTMusicConnectCard() {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accentColor.withValues(alpha: 0.6),
            _accentColor.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accentColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          // Icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Iconsax.music, size: 32, color: _accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.signInWithGoogle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'One sign-in for your YouTube Music library, listening history, '
            'profile and Jams.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _login,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(l10n.signInWithGoogle),
            style: FilledButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: _colors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Appearance (Theme mode only — colors are dynamic from album art) ─

  Widget _buildAppearanceSection() {
    final currentThemeMode = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(appLocaleProvider);
    final currentContentCountry = ref.watch(appContentCountryProvider);
    final l10n = context.l10n;

    return _sectionCard(
      children: [
        _sectionHeader(l10n.appearance, Iconsax.brush_1),
        const SizedBox(height: 16),

        // Theme mode selector
        Text(
          l10n.theme,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: InzxThemeMode.values.map((mode) {
            final selected = mode == currentThemeMode;
            final label = mode == InzxThemeMode.system
                ? l10n.themeAuto
                : mode == InzxThemeMode.light
                ? l10n.themeLight
                : l10n.themeDark;
            final icon = mode == InzxThemeMode.system
                ? Iconsax.autobrightness
                : mode == InzxThemeMode.light
                ? Iconsax.sun_1
                : Iconsax.moon;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: mode != InzxThemeMode.dark ? 8 : 0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected
                        ? _accentColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? _accentColor.withValues(alpha: 0.4)
                          : (_isDark
                                ? InzxColors.darkBorder
                                : InzxColors.border),
                    ),
                  ),
                  child: InkWell(
                    onTap: () =>
                        ref.read(themeModeProvider.notifier).setThemeMode(mode),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: selected ? _accentColor : _textTertiary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected ? _accentColor : _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

        // Accent Color selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.accentColor,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
            if (ref.watch(accentColorProvider) == InzxAccentColor.custom)
              GestureDetector(
                onTap: () => _openCustomColorPicker(ref.read(customAccentColorProvider)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${ref.watch(customAccentColorProvider).toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _accentColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...pickerAccentColors.map((preset) {
                final isSelected = ref.watch(accentColorProvider) == preset;
                final presetColor = accentSwatchColor(preset, isDark: _isDark);
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(accentColorProvider.notifier)
                          .setAccentColor(preset);
                    },
                    child: Tooltip(
                      message: getAccentColorName(preset),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: presetColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : (_isDark ? Colors.white12 : Colors.black12),
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: presetColor.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              }),
              // Custom Color Wheel Button
              Consumer(
                builder: (context, refConsumer, _) {
                  final isCustomSelected =
                      refConsumer.watch(accentColorProvider) == InzxAccentColor.custom;
                  final currentCustom = refConsumer.watch(customAccentColorProvider);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => _openCustomColorPicker(currentCustom),
                      child: Tooltip(
                        message: l10n.customColorWheel,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: isCustomSelected
                                ? null
                                : const SweepGradient(
                                    colors: [
                                      Colors.red,
                                      Colors.yellow,
                                      Colors.green,
                                      Colors.cyan,
                                      Colors.blue,
                                      Colors.purple,
                                      Colors.red,
                                    ],
                                  ),
                            color: isCustomSelected ? currentCustom : null,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isCustomSelected
                                  ? Colors.white
                                  : (_isDark ? Colors.white24 : Colors.black12),
                              width: isCustomSelected ? 3 : 1.5,
                            ),
                            boxShadow: isCustomSelected
                                ? [
                                    BoxShadow(
                                      color: currentCustom.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Icon(
                              isCustomSelected ? Icons.check : Iconsax.colorfilter,
                              color: isCustomSelected
                                  ? (currentCustom.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white)
                                  : Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Dynamic colours: follow the artwork, or stay on the accent above
        _switchTile(
          icon: Iconsax.colorfilter,
          iconBg: _accentColor,
          title: 'Dynamic colours',
          subtitle: ref.watch(dynamicColorsEnabledProvider)
              ? l10n.dynamicColorsNote
              : 'Off: the app uses your accent colour. Now Playing still follows the artwork.',
          value: ref.watch(dynamicColorsEnabledProvider),
          onChanged: (enabled) {
            HapticFeedback.selectionClick();
            ref.read(dynamicColorsEnabledProvider.notifier).setEnabled(enabled);
          },
        ),
        const SizedBox(height: 18),

        // Language & Region
        Text(
          l10n.languageAndRegion,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        _settingsTile(
          icon: Iconsax.language_square,
          iconBg: _accentColor,
          title: l10n.language,
          subtitle: _languageLabel(currentLocale),
          onTap: _showLanguageSelector,
        ),
        Divider(
          height: 1,
          color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
        ),
        _settingsTile(
          icon: Icons.public_rounded,
          iconBg: _colors.secondary,
          title: l10n.contentLocation,
          subtitle: _contentLocationLabel(currentContentCountry),
          onTap: _showContentLocationSelector,
        ),
        Divider(
          height: 1,
          color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
        ),
        // Player & Now Playing — dedicated screen for the many player
        // appearance options (style, progress bar, album art motion, lyrics).
        _settingsTile(
          icon: Icons.play_circle_fill_rounded,
          iconBg: _accentColor,
          title: l10n.playerAndNowPlaying,
          subtitle: l10n.playerAndNowPlayingSubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlayerAppearanceScreen()),
          ),
        ),
        const SizedBox(height: 18),

        // Advanced
        Text(
          l10n.advanced,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        _switchTile(
          icon: Iconsax.status,
          iconBg: _accentColor,
          title: l10n.statsForNerds,
          subtitle: l10n.statsForNerdsSubtitle,
          value: ref.watch(showNerdStatsProvider),
          onChanged: (val) =>
              ref.read(audioPlayerServiceProvider).setShowNerdStats(val),
        ),
      ],
    );
  }

  Future<void> _openCustomColorPicker(Color initialColor) async {
    final pickedColor = await ColorPickerDialog.show(
      context,
      initialColor: initialColor,
    );
    if (pickedColor != null) {
      await ref.read(customAccentColorProvider.notifier).setCustomColor(pickedColor);
      await ref.read(accentColorProvider.notifier).setAccentColor(InzxAccentColor.custom);
    }
  }

  // ── Quick Actions (Audio, Downloads, Backup) ──────────────────────

  Widget _buildQuickActions() {
    final l10n = context.l10n;
    return _sectionCard(
      children: [
        _sectionHeader(l10n.quickActions, Iconsax.setting_2),
        const SizedBox(height: 12),
        _settingsTile(
          icon: Iconsax.music,
          iconBg: _accentColor,
          title: l10n.audio,
          subtitle: l10n.audioQuickActionsSubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AudioSettingsScreen()),
          ),
        ),
        Divider(
          height: 1,
          color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
        ),
        _settingsTile(
          icon: Iconsax.document_download,
          iconBg: _colors.tertiary,
          title: l10n.downloads,
          subtitle: l10n.downloadsQuickActionsSubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DownloadSettingsScreen()),
          ),
        ),
        Divider(
          height: 1,
          color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
        ),
        _settingsTile(
          icon: Iconsax.document_upload,
          iconBg: _colors.secondary,
          title: l10n.backupRestore,
          subtitle: l10n.backupRestoreQuickActionsSubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
          ),
        ),
        Divider(
          height: 1,
          color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
        ),
        ValueListenableBuilder<DiscordRpcState>(
          valueListenable: DiscordRpcService.instance.stateNotifier,
          builder: (context, rpcState, _) {
            final connected = DiscordRpcService.instance.isAuthorized;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF5865F2).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: DiscordLogo(size: 20, color: Color(0xFF5865F2)),
                ),
              ),
              title: Text(
                'Discord Rich Presence',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                connected
                    ? 'Connected as ${rpcState.displayName}'
                    : 'Show your listening activity on Discord',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
              trailing: Icon(Iconsax.arrow_right_3, size: 18, color: _textTertiary),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DiscordRichPresenceScreen(),
                ),
              ),
            );
          },
        ),
        ListenableBuilder(
          listenable: ScrobbleService.instance,
          builder: (context, _) {
            final svc = ScrobbleService.instance;
            final connected = [
              if (svc.lastFmSignedIn) 'Last.fm',
              if (svc.listenBrainzSignedIn) 'ListenBrainz',
            ];
            return _settingsTile(
              icon: Iconsax.radar,
              iconBg: _accentColor,
              title: 'Scrobbling',
              subtitle: connected.isEmpty
                  ? 'Last.fm and ListenBrainz'
                  : 'Connected: ${connected.join(' & ')}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScrobblingScreen()),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconBg, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: _textPrimary,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: _textSecondary),
      ),
      trailing: Icon(Iconsax.arrow_right_3, size: 18, color: _textTertiary),
      onTap: onTap,
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconBg, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: _textPrimary,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: _textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: InzxColors.contrastTextOn(_accentColor),
        activeTrackColor: _accentColor,
        inactiveThumbColor: _isDark ? Colors.white70 : Colors.white,
        inactiveTrackColor: _isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.grey.shade300,
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        trackOutlineWidth: WidgetStateProperty.all(0.0),
      ),
    );
  }

  // ── Google Account ─────────────────────────────────────────────────

  String _languageLabel(Locale? locale) {
    final l10n = context.l10n;
    switch (appLanguageOptionFromLocale(locale)) {
      case AppLanguageOption.system:
        return l10n.languageSystem;
      case AppLanguageOption.english:
        return l10n.languageEnglish;
      case AppLanguageOption.turkish:
        return l10n.languageTurkish;
      case AppLanguageOption.russian:
        return l10n.languageRussian;
      case AppLanguageOption.hindi:
        return l10n.languageHindi;
      case AppLanguageOption.malayalam:
        return l10n.languageMalayalam;
      case AppLanguageOption.tamil:
        return l10n.languageTamil;
      case AppLanguageOption.kannada:
        return l10n.languageKannada;
      case AppLanguageOption.telugu:
        return l10n.languageTelugu;
      case AppLanguageOption.spanish:
        return l10n.languageSpanish;
      case AppLanguageOption.french:
        return l10n.languageFrench;
      case AppLanguageOption.german:
        return l10n.languageGerman;
      case AppLanguageOption.indonesian:
        return l10n.languageIndonesian;
      case AppLanguageOption.japanese:
        return l10n.languageJapanese;
      case AppLanguageOption.korean:
        return l10n.languageKorean;
      case AppLanguageOption.arabic:
        return l10n.languageArabic;
      case AppLanguageOption.ukrainian:
        return l10n.languageUkrainian;
      case AppLanguageOption.thai:
        return l10n.languageThai;
      case AppLanguageOption.portugueseBrazil:
        return l10n.languagePortugueseBrazil;
      case AppLanguageOption.chineseSimplified:
        return l10n.languageChineseSimplified;
      case AppLanguageOption.chineseTraditional:
        return l10n.languageChineseTraditional;
    }
  }

  String _contentLocationLabel(String? countryCode) {
    final l10n = context.l10n;
    switch (appContentLocationOptionFromCountryCode(countryCode)) {
      case AppContentLocationOption.system:
        return l10n.locationSystem;
      case AppContentLocationOption.unitedStates:
        return l10n.locationUnitedStates;
      case AppContentLocationOption.india:
        return l10n.locationIndia;
      case AppContentLocationOption.turkey:
        return l10n.locationTurkey;
      case AppContentLocationOption.russia:
        return l10n.locationRussia;
    }
  }

  List<String> _languageSearchTerms(AppLanguageOption option, String label) {
    switch (option) {
      case AppLanguageOption.system:
        return [label, 'system', 'default', 'auto'];
      case AppLanguageOption.english:
        return [label, 'english', 'en'];
      case AppLanguageOption.turkish:
        return [label, 'turkish', 'turkce', 'tuerkce', 'tr'];
      case AppLanguageOption.russian:
        return [label, 'russian', 'russian', 'русский', 'ru'];
      case AppLanguageOption.hindi:
        return [label, 'hindi', 'हिन्दी', 'hi'];
      case AppLanguageOption.malayalam:
        return [label, 'malayalam', 'മലയാളം', 'ml'];
      case AppLanguageOption.tamil:
        return [label, 'tamil', 'தமிழ்', 'ta'];
      case AppLanguageOption.kannada:
        return [label, 'kannada', 'ಕನ್ನಡ', 'kn'];
      case AppLanguageOption.telugu:
        return [label, 'telugu', 'తెలుగు', 'te'];
      case AppLanguageOption.spanish:
        return [label, 'spanish', 'espanol', 'español', 'es'];
      case AppLanguageOption.french:
        return [label, 'french', 'francais', 'français', 'fr'];
      case AppLanguageOption.german:
        return [label, 'german', 'deutsch', 'de'];
      case AppLanguageOption.indonesian:
        return [label, 'indonesian', 'bahasa indonesia', 'id'];
      case AppLanguageOption.japanese:
        return [label, 'japanese', '日本語', 'ja'];
      case AppLanguageOption.korean:
        return [label, 'korean', '한국어', 'ko'];
      case AppLanguageOption.arabic:
        return [label, 'arabic', 'العربية', 'ar'];
      case AppLanguageOption.ukrainian:
        return [label, 'ukrainian', 'українська', 'uk'];
      case AppLanguageOption.thai:
        return [label, 'thai', 'ไทย', 'th'];
      case AppLanguageOption.portugueseBrazil:
        return [
          label,
          'portuguese',
          'brazilian portuguese',
          'português',
          'pt-br',
        ];
      case AppLanguageOption.chineseSimplified:
        return [label, 'chinese', 'simplified chinese', '简体中文', 'zh-hans'];
      case AppLanguageOption.chineseTraditional:
        return [label, 'chinese', 'traditional chinese', '繁體中文', 'zh-hant'];
    }
  }

  List<String> _contentLocationSearchTerms(
    AppContentLocationOption option,
    String label,
  ) {
    switch (option) {
      case AppContentLocationOption.system:
        return [label, 'system', 'default', 'auto'];
      case AppContentLocationOption.unitedStates:
        return [label, 'united states', 'usa', 'us', 'america'];
      case AppContentLocationOption.india:
        return [label, 'india', 'in'];
      case AppContentLocationOption.turkey:
        return [label, 'turkey', 'turkiye', 'tr'];
      case AppContentLocationOption.russia:
        return [label, 'russia', 'ru'];
    }
  }

  Future<void> _showLanguageSelector() async {
    final currentOption = appLanguageOptionFromLocale(
      ref.read(appLocaleProvider),
    );
    final l10n = context.l10n;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _backgroundColor,
      builder: (sheetContext) {
        var query = '';
        final options = <(AppLanguageOption option, String label)>[
          (AppLanguageOption.system, l10n.languageSystem),
          (AppLanguageOption.english, l10n.languageEnglish),
          (AppLanguageOption.turkish, l10n.languageTurkish),
          (AppLanguageOption.russian, l10n.languageRussian),
          (AppLanguageOption.hindi, l10n.languageHindi),
          (AppLanguageOption.malayalam, l10n.languageMalayalam),
          (AppLanguageOption.tamil, l10n.languageTamil),
          (AppLanguageOption.kannada, l10n.languageKannada),
          (AppLanguageOption.telugu, l10n.languageTelugu),
          (AppLanguageOption.spanish, l10n.languageSpanish),
          (AppLanguageOption.french, l10n.languageFrench),
          (AppLanguageOption.german, l10n.languageGerman),
          (AppLanguageOption.indonesian, l10n.languageIndonesian),
          (AppLanguageOption.japanese, l10n.languageJapanese),
          (AppLanguageOption.korean, l10n.languageKorean),
          (AppLanguageOption.arabic, l10n.languageArabic),
          (AppLanguageOption.ukrainian, l10n.languageUkrainian),
          (AppLanguageOption.thai, l10n.languageThai),
          (AppLanguageOption.portugueseBrazil, l10n.languagePortugueseBrazil),
          (AppLanguageOption.chineseSimplified, l10n.languageChineseSimplified),
          (
            AppLanguageOption.chineseTraditional,
            l10n.languageChineseTraditional,
          ),
        ];

        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                final normalizedQuery = query.trim().toLowerCase();
                final filteredOptions = options.where((item) {
                  if (normalizedQuery.isEmpty) return true;
                  return _languageSearchTerms(
                    item.$1,
                    item.$2,
                  ).any((term) => term.toLowerCase().contains(normalizedQuery));
                }).toList();

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.chooseLanguage,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: Icon(
                                Icons.close_rounded,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (value) {
                            setModalState(() {
                              query = value;
                            });
                          },
                          style: TextStyle(color: _textPrimary),
                          decoration: InputDecoration(
                            hintText: l10n.searchLanguagesHint,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: _textTertiary,
                            ),
                            filled: true,
                            fillColor: _isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filteredOptions.isEmpty
                              ? Center(
                                  child: Text(
                                    l10n.noMatchingLanguages,
                                    style: TextStyle(color: _textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: filteredOptions.length,
                                  itemBuilder: (context, index) {
                                    final item = filteredOptions[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        item.$2,
                                        style: TextStyle(color: _textPrimary),
                                      ),
                                      trailing: item.$1 == currentOption
                                          ? Icon(
                                              Icons.check_rounded,
                                              color: _accentColor,
                                            )
                                          : null,
                                      onTap: () async {
                                        final selectedLocale =
                                            localeForAppLanguageOption(item.$1);
                                        final activeLocale = ref.read(
                                          appLocaleProvider,
                                        );
                                        final activeCode = activeLocale == null
                                            ? ''
                                            : appLocaleStorageKey(activeLocale);
                                        final selectedCode =
                                            selectedLocale == null
                                            ? ''
                                            : appLocaleStorageKey(
                                                selectedLocale,
                                              );

                                        if (activeCode == selectedCode) {
                                          Navigator.pop(sheetContext);
                                          return;
                                        }

                                        Navigator.pop(sheetContext);
                                        await ref
                                            .read(appLocaleProvider.notifier)
                                            .setLocale(selectedLocale);
                                        requestAppRestart?.call();
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showContentLocationSelector() async {
    final currentOption = appContentLocationOptionFromCountryCode(
      ref.read(appContentCountryProvider),
    );
    final l10n = context.l10n;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _backgroundColor,
      builder: (sheetContext) {
        var query = '';
        final options = <(AppContentLocationOption option, String label)>[
          (AppContentLocationOption.system, l10n.locationSystem),
          (AppContentLocationOption.unitedStates, l10n.locationUnitedStates),
          (AppContentLocationOption.india, l10n.locationIndia),
          (AppContentLocationOption.turkey, l10n.locationTurkey),
          (AppContentLocationOption.russia, l10n.locationRussia),
        ];

        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                final normalizedQuery = query.trim().toLowerCase();
                final filteredOptions = options.where((item) {
                  if (normalizedQuery.isEmpty) return true;
                  return _contentLocationSearchTerms(
                    item.$1,
                    item.$2,
                  ).any((term) => term.toLowerCase().contains(normalizedQuery));
                }).toList();

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.chooseContentLocation,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: Icon(
                                Icons.close_rounded,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (value) {
                            setModalState(() {
                              query = value;
                            });
                          },
                          style: TextStyle(color: _textPrimary),
                          decoration: InputDecoration(
                            hintText: l10n.searchLocationsHint,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: _textTertiary,
                            ),
                            filled: true,
                            fillColor: _isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filteredOptions.isEmpty
                              ? Center(
                                  child: Text(
                                    l10n.noMatchingLocations,
                                    style: TextStyle(color: _textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: filteredOptions.length,
                                  itemBuilder: (context, index) {
                                    final item = filteredOptions[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        item.$2,
                                        style: TextStyle(color: _textPrimary),
                                      ),
                                      trailing: item.$1 == currentOption
                                          ? Icon(
                                              Icons.check_rounded,
                                              color: _accentColor,
                                            )
                                          : null,
                                      onTap: () async {
                                        final selectedCountryCode =
                                            countryCodeForContentLocationOption(
                                              item.$1,
                                            );
                                        final activeCountryCode =
                                            normalizeContentCountryCode(
                                              ref.read(
                                                appContentCountryProvider,
                                              ),
                                            );
                                        final selectedCode =
                                            normalizeContentCountryCode(
                                              selectedCountryCode,
                                            );

                                        if (activeCountryCode == selectedCode) {
                                          Navigator.pop(sheetContext);
                                          return;
                                        }

                                        Navigator.pop(sheetContext);
                                        await ref
                                            .read(
                                              appContentCountryProvider
                                                  .notifier,
                                            )
                                            .setCountryCode(
                                              selectedCountryCode,
                                            );
                                        requestAppRestart?.call();
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Profile card for the app's single sign-in (Google account via
  /// YouTube Music) — it powers library sync, history, profile and Jams.
  Widget _buildAccountSection(YTMusicAuthState authState) {
    final l10n = context.l10n;
    final account = authState.account;
    final subtitle = account?.email ?? account?.handle ?? l10n.youtubeMusicLabel;

    Widget initialsAvatar() => Center(
      child: Text(
        account?.initials ?? 'U',
        style: TextStyle(
          color: _colors.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );

    return _sectionCard(
      children: [
        _sectionHeader(l10n.yourProfile, Iconsax.user),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_accentColor, _accentColor.withValues(alpha: 0.6)],
                ),
              ),
              child: ClipOval(
                child: account?.avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: account!.avatarUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => initialsAvatar(),
                        errorWidget: (_, _, _) => initialsAvatar(),
                      )
                    : initialsAvatar(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account?.name ?? l10n.connected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Library · History · Jams',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Sync Section ───────────────────────────────────────────────────

  Widget _buildSyncSection() {
    final l10n = context.l10n;
    final syncService = ref.watch(ytMusicSyncServiceProvider);

    return _sectionCard(
      children: [
        _sectionHeader(l10n.sync, Iconsax.refresh),
        const SizedBox(height: 12),
        if (syncService.lastSync != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Iconsax.clock, size: 14, color: _textTertiary),
                const SizedBox(width: 6),
                Text(
                  l10n.lastSynced(_formatDate(syncService.lastSync!)),
                  style: TextStyle(color: _textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        if (_lastSyncResult != null && _lastSyncResult!.success)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: _accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.syncedItems(_lastSyncResult!.itemsSynced),
                      style: TextStyle(
                        color: _accentColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSyncing ? null : _sync,
            icon: _isSyncing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _colors.onPrimary,
                    ),
                  )
                : const Icon(Iconsax.refresh, size: 18),
            label: Text(_isSyncing ? l10n.syncing : l10n.syncNow),
            style: FilledButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: _colors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Cache Management ───────────────────────────────────────────────

  Widget _buildCacheSection() {
    final l10n = context.l10n;
    final cacheManager = ref.watch(cacheManagementProvider);

    return _sectionCard(
      children: [
        _sectionHeader(l10n.streamingCache, Iconsax.cpu),
        const SizedBox(height: 12),
        FutureBuilder(
          future: cacheManager.getCacheStats(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final stats = snapshot.data!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.cachedItems(stats.totalItemCount),
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _cacheChip(l10n.streams, stats.streamUrlsCount),
                        _cacheChip(l10n.home, stats.homePageCount),
                        _cacheChip(l10n.lyricsTab, stats.lyricsCount),
                        _cacheChip(l10n.albums, stats.albumsCount),
                        _cacheChip(l10n.artists, stats.artistsCount),
                        _cacheChip(l10n.playlists, stats.playlistsCount),
                        _cacheChip(l10n.colors, stats.colorsCount),
                        _cacheChip(l10n.searches, stats.cachedSearchesCount),
                      ],
                    ),
                    if (stats.expiredEntriesCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.expiredCount(stats.expiredEntriesCount),
                        style: TextStyle(color: _textTertiary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accentColor,
                ),
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await cacheManager.cleanupExpiredCache();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.cacheCleanupComplete,
                          style: TextStyle(color: _colors.onInverseSurface),
                        ),
                        backgroundColor: _colors.inverseSurface,
                      ),
                    );
                    setState(() {});
                  }
                },
                icon: Icon(Iconsax.refresh, size: 16, color: _accentColor),
                label: Text(
                  l10n.cleanUp,
                  style: TextStyle(color: _accentColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _accentColor.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.clearCache),
                      content: Text(l10n.clearCachedMusicDataConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            l10n.clear,
                            style: TextStyle(color: _colors.error),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await cacheManager.clearAllCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.cacheCleared,
                            style: TextStyle(color: _colors.onInverseSurface),
                          ),
                          backgroundColor: _colors.inverseSurface,
                        ),
                      );
                      setState(() {});
                    }
                  }
                },
                icon: Icon(Iconsax.trash, size: 16, color: _colors.error),
                label: Text(
                  l10n.clearAll,
                  style: TextStyle(color: _colors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _colors.error.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cacheChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 12,
          color: _accentColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Cache Analytics ────────────────────────────────────────────────

  Widget _buildAnalyticsSection() {
    final l10n = context.l10n;
    final analytics = ref.watch(cacheAnalyticsProvider);

    return _sectionCard(
      children: [
        _sectionHeader(l10n.analytics, Iconsax.chart_2),
        const SizedBox(height: 14),
        // Hit rate progress indicator
        _buildHitRateIndicator(analytics.hitRate),
        const SizedBox(height: 16),
        Row(
          children: [
            _analyticsPill(l10n.hits, analytics.cacheHits, _accentColor),
            const SizedBox(width: 8),
            _analyticsPill(l10n.misses, analytics.cacheMisses, _colors.error),
            const SizedBox(width: 8),
            _analyticsPill(
              l10n.network,
              analytics.networkCalls,
              _colors.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              analytics.reset();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.analyticsReset,
                    style: TextStyle(color: _colors.onInverseSurface),
                  ),
                  backgroundColor: _colors.inverseSurface,
                ),
              );
            },
            icon: Icon(Iconsax.refresh, size: 16, color: _textSecondary),
            label: Text(
              l10n.resetStats,
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHitRateIndicator(double hitRate) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.cacheHitRate,
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            Text(
              '${hitRate.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: hitRate / 100,
            minHeight: 6,
            backgroundColor: _accentColor.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
          ),
        ),
      ],
    );
  }

  Widget _analyticsPill(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: _textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── Library Stats ──────────────────────────────────────────────────

  Widget _buildLibraryStats() {
    final l10n = context.l10n;
    final likedSongs = ref.watch(ytMusicLikedSongsProvider);
    final savedAlbums = ref.watch(ytMusicSavedAlbumsProvider);
    final savedPlaylists = ref.watch(ytMusicSavedPlaylistsProvider);
    final subscribedArtists = ref.watch(ytMusicLibrarySubscriptionsProvider);

    return _sectionCard(
      children: [
        _sectionHeader(l10n.library, Iconsax.music_library_2),
        const SizedBox(height: 16),
        Row(
          children: [
            _libraryStat(
              Iconsax.heart5,
              l10n.liked,
              likedSongs.when(
                data: (s) => '${s.length}',
                loading: () => '…',
                error: (_, _) => '-',
              ),
            ),
            _libraryStat(
              Iconsax.music_square,
              l10n.albums,
              savedAlbums.when(
                data: (a) => '${a.length}',
                loading: () => '…',
                error: (_, _) => '-',
              ),
            ),
            _libraryStat(
              Iconsax.music_playlist,
              l10n.playlists,
              savedPlaylists.when(
                data: (p) => '${p.length}',
                loading: () => '…',
                error: (_, _) => '-',
              ),
            ),
            _libraryStat(
              Iconsax.user,
              l10n.artists,
              subscribedArtists.when(
                data: (a) => '${a.length}',
                loading: () => '…',
                error: (_, _) => '-',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _libraryStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: _accentColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: _textSecondary)),
        ],
      ),
    );
  }

  // ── OTA Debug ──────────────────────────────────────────────────────

  /// Bottom sheet offering ways to support the project: GitHub Sponsors
  /// and a UPI QR code for direct donations.
  Future<void> _showSupportSheet() async {
    final sheetBg = _isDark ? Colors.black : Colors.white;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF48FB1).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Iconsax.heart5,
                        color: Color(0xFFF06292),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Support Inzx',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Inzx is free and open source. Your support helps keep it '
                  'alive and actively maintained. Every bit is appreciated!',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 18),

                // GitHub Sponsors
                Material(
                  color: _isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      launchUrl(
                        Uri.parse('https://github.com/sponsors/nirmaleeswar30'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Iconsax.card, color: _accentColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GitHub Sponsors',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'One-time or monthly on GitHub',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Iconsax.export_3, size: 18, color: _textTertiary),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // UPI QR
                Center(
                  child: Text(
                    'Or pay via UPI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/upi.jpeg',
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Scan with any UPI app to donate',
                    style: TextStyle(fontSize: 12, color: _textTertiary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOtaDebugSection() {
    final l10n = context.l10n;
    final updater = ShorebirdUpdater();

    return _sectionCard(
      children: [
        _sectionHeader(l10n.appInfo, Iconsax.info_circle),
        const SizedBox(height: 12),
        // Share behavior
        _switchTile(
          icon: Iconsax.share,
          iconBg: _accentColor,
          title: l10n.shareYoutubeMusicLinks,
          subtitle: l10n.shareYoutubeMusicLinksSubtitle,
          value: ref.watch(shareNativeLinksProvider),
          onChanged: (val) =>
              ref.read(shareNativeLinksProvider.notifier).setEnabled(val),
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 16),
        // Check for App Updates
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Iconsax.refresh_circle, color: _accentColor, size: 18),
          ),
          title: Text(
            'Check for App Updates',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          subtitle: Text(
            'Check GitHub & OTA for new versions and updates',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _textSecondary,
          ),
          onTap: _handleCheckForUpdates,
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 16),
        // What's New & Changelog
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Iconsax.document_text, color: _accentColor, size: 18),
          ),
          title: Text(
            'What\'s New',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          subtitle: Text(
            'View release notes, changelogs & new features',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _textSecondary,
          ),
          onTap: () => WhatsNewDialog.show(context),
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 16),
        // App Info Details Popup
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Iconsax.device_message, color: _accentColor, size: 18),
          ),
          title: Text(
            'Version Details',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          subtitle: Text(
            'App logo, version, patch number & credits',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _textSecondary,
          ),
          onTap: _showAppInfoPopup,
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 16),
        // App Logs & Crash Diagnostics
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Iconsax.document_code, color: _accentColor, size: 18),
          ),
          title: Text(
            'App Logs & Diagnostics',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          subtitle: Text(
            'View, copy & export crash traces',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _textSecondary,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AppLogsScreen()),
            );
          },
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 16),
        // Sponsor Inzx
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF48FB1).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Iconsax.heart5,
              color: Color(0xFFF06292), // Pastel pink
              size: 18,
            ),
          ),
          title: Text(
            'Sponsor Inzx',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          subtitle: Text(
            'Support the development via GitHub Sponsors or UPI',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _textSecondary,
          ),
          onTap: _showSupportSheet,
        ),
        Divider(color: _isDark ? Colors.white10 : Colors.black12, height: 24),
        _debugRow(l10n.releaseBuild, kReleaseMode ? l10n.yes : l10n.no),
        _debugRow(
          l10n.updater,
          updater.isAvailable ? l10n.available : l10n.unavailable,
        ),
        FutureBuilder<Patch?>(
          future: updater.readCurrentPatch(),
          builder: (context, snapshot) {
            final label = snapshot.connectionState == ConnectionState.waiting
                ? l10n.loadingCompact
                : snapshot.hasError
                ? l10n.errorCompact
                : snapshot.data == null
                ? l10n.none
                : '#${snapshot.data!.number}';
            return _debugRow(l10n.currentPatch, label);
          },
        ),
        FutureBuilder<Patch?>(
          future: updater.readNextPatch(),
          builder: (context, snapshot) {
            final label = snapshot.connectionState == ConnectionState.waiting
                ? l10n.loadingCompact
                : snapshot.hasError
                ? l10n.errorCompact
                : snapshot.data == null
                ? l10n.none
                : '#${snapshot.data!.number}';
            return _debugRow(l10n.nextPatch, label);
          },
        ),
      ],
    );
  }

  void _handleCheckForUpdates() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 14),
            Text('Checking GitHub and OTA for updates...'),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    // 1. Check Shorebird OTA patch updates first
    final patchUpdated = await ShorebirdUpdateService.instance.checkForUpdates();
    if (!mounted) return;

    if (patchUpdated) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('OTA Patch Installed!', style: TextStyle(color: _textPrimary)),
          content: Text(
            'A new patch has been downloaded and installed. Please restart the app to apply changes.',
            style: TextStyle(color: _textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Later', style: TextStyle(color: _textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Restart App'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Check GitHub Releases API for new release build
    final releaseInfo = await GithubReleaseUpdateService.instance.checkForNewRelease(
      ignoreReleaseMode: true,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (releaseInfo != null) {
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _accentColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.arrow_circle_down, size: 48, color: _accentColor),
                    const SizedBox(height: 16),
                    Text(
                      'New Update Available!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Version ${releaseInfo.latestVersion} is now available on GitHub.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _textSecondary),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: _accentColor),
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              launchUrl(
                                Uri.parse(releaseInfo.downloadUrl),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download & Update'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
              SizedBox(width: 10),
              Text('You are on the latest version!'),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAppInfoPopup() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final updater = ShorebirdUpdater();
    Patch? currentPatch;
    try {
      currentPatch = await updater.readCurrentPatch();
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final patchText = currentPatch != null
            ? '#${currentPatch.number}'
            : 'Base Release';

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _accentColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          _isDark ? 'assets/icon/logo_dark.png' : 'assets/icon/logo_light.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: _accentColor.withValues(alpha: 0.15),
                            child: Icon(Iconsax.music5, size: 40, color: _accentColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Inzx Music',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${packageInfo.version} (Build ${packageInfo.buildNumber})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _textPrimary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _textPrimary.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        children: [
                          _popupInfoRow('App Version', packageInfo.version),
                          Divider(height: 16, color: _textPrimary.withValues(alpha: 0.08)),
                          _popupInfoRow('Build Number', packageInfo.buildNumber),
                          Divider(height: 16, color: _textPrimary.withValues(alpha: 0.08)),
                          _popupInfoRow('Patch Number', patchText),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              launchUrl(
                                Uri.parse('https://github.com/nirmaleeswar30/Inzx'),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            icon: Icon(Iconsax.code, size: 16, color: _accentColor),
                            label: Text(
                              'GitHub',
                              style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _accentColor.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: FilledButton.styleFrom(
                              backgroundColor: _accentColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
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

  Widget _popupInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: _textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Logout ─────────────────────────────────────────────────────────

  Widget _buildLogoutButton() {
    final l10n = context.l10n;
    // Use a more visible error color for light mode
    final errorColor = _isDark ? _colors.error : const Color(0xFFC62828);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: Icon(Iconsax.logout, color: errorColor, size: 18),
        label: Text(l10n.disconnectYoutubeMusic),
        style: OutlinedButton.styleFrom(
          foregroundColor: errorColor,
          side: BorderSide(color: errorColor.withValues(alpha: 0.5)),
          backgroundColor: errorColor.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _login() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const YTMusicLoginScreen()),
    );

    if (result == true) {
      await _refreshLikedSongsWithLog(reason: 'login');
      ref.invalidate(ytMusicSavedAlbumsProvider);
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      ref.invalidate(ytMusicLibrarySubscriptionsProvider);
    }
  }

  Future<void> _sync() async {
    final l10n = context.l10n;
    setState(() => _isSyncing = true);

    final syncService = ref.read(ytMusicSyncServiceProvider);
    final result = await syncService.syncAll();

    setState(() {
      _isSyncing = false;
      _lastSyncResult = result;
    });

    if (result.success) {
      await _refreshLikedSongsWithLog(reason: 'sync');
      ref.invalidate(ytMusicSavedAlbumsProvider);
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      ref.invalidate(ytMusicLibrarySubscriptionsProvider);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.syncFailed(result.error ?? 'unknown')),
          backgroundColor: _colors.error,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.disconnectYoutubeMusicQuestion),
        content: Text(l10n.disconnectYoutubeMusicWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _colors.error),
            child: Text(l10n.disconnect),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ytMusicAuthStateProvider.notifier).logout();
      await ref.read(ytMusicSyncServiceProvider).clearCache();
    }
  }

  Future<void> _refreshLikedSongsWithLog({required String reason}) async {
    try {
      final songs = await ref.refresh(ytMusicLikedSongsProvider.future);
      if (!kReleaseMode) {
        debugPrint(
          'YTMusicSettings: liked songs refreshed ($reason) -> ${songs.length} tracks',
        );
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('YTMusicSettings: liked songs refresh failed ($reason): $e');
      }
      ref.invalidate(ytMusicLikedSongsProvider);
    }
  }

  String _formatDate(DateTime date) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else {
      return l10n.daysAgo(diff.inDays);
    }
  }
}

/// A section with search tags paired with its widget for filtering.
class _TaggedSection {
  final List<String> tags;
  final Widget widget;
  const _TaggedSection(this.tags, this.widget);
}

/// A deep-link searchable item that navigates to a specific screen or triggers an action.
class _SearchableItem {
  final List<String> tags;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? screen;
  final VoidCallback? onTap;

  List<String> get searchTerms => [...tags, title, subtitle];

  const _SearchableItem({
    required this.tags,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.screen,
    this.onTap,
  }) : assert(
         screen != null || onTap != null,
         'Either screen or onTap must be provided',
       );
}
