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
import '../services/auth/google_auth_service.dart';
import '../services/ytmusic_sync_service.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../../core/providers/theme_provider.dart';
import '../../main.dart';
import 'ytmusic_login_screen.dart';
import 'audio_settings_screen.dart';
import 'download_settings_screen.dart';
import 'backup_restore_screen.dart';

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

  /// Deep-link searchable items from nested screens (Audio, Downloads, Backup)
  List<_SearchableItem> get _deepSearchItems {
    final l10n = context.l10n;
    return [
      // Audio Settings
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
        ],
        title: l10n.streamingQuality,
        subtitle: l10n.streamingQualitySubtitle,
        icon: Iconsax.volume_high,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: ['crossfade', 'transition', 'blend', 'gapless', 'playback'],
        title: l10n.crossfadeTransition,
        subtitle: l10n.crossfadeTransitionSubtitle,
        icon: Iconsax.blend,
        screen: const AudioSettingsScreen(),
      ),
      _SearchableItem(
        tags: ['streaming', 'cache', 'buffer', 'preload', 'wifi'],
        title: l10n.streamingCache,
        subtitle: l10n.streamingCacheSubtitle,
        icon: Iconsax.cpu,
        screen: const AudioSettingsScreen(),
      ),
      // Download Settings
      _SearchableItem(
        tags: ['download', 'quality', 'offline', 'bitrate'],
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
        ],
        title: l10n.downloadLocation,
        subtitle: l10n.downloadLocationSubtitle,
        icon: Iconsax.folder_2,
        screen: const DownloadSettingsScreen(),
      ),
      _SearchableItem(
        tags: ['data', 'usage', 'network', 'bandwidth', 'mobile'],
        title: l10n.dataUsageInfo,
        subtitle: l10n.dataUsageInfoSubtitle,
        icon: Iconsax.chart_1,
        screen: const DownloadSettingsScreen(),
      ),
      // Backup & Restore
      _SearchableItem(
        tags: ['backup', 'export', 'save', 'file'],
        title: l10n.createBackup,
        subtitle: l10n.createBackupSubtitle,
        icon: Iconsax.export_1,
        screen: const BackupRestoreScreen(),
      ),
      _SearchableItem(
        tags: ['restore', 'import', 'load', 'file'],
        title: l10n.restoreBackup,
        subtitle: l10n.restoreBackupSubtitle,
        icon: Iconsax.import_1,
        screen: const BackupRestoreScreen(),
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => item.screen),
                ),
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

  List<_TaggedSection> _loggedOutSections() => [
    _TaggedSection([
      context.l10n.yourProfile,
      context.l10n.signInWithGoogle,
      context.l10n.googleUser,
      'profile',
      'google',
      'account',
      'sign in',
    ], _buildGoogleAccountSection()),
    _TaggedSection([
      context.l10n.connectYoutubeMusic,
      context.l10n.connectYoutubeMusicSubtitle,
      context.l10n.connectYtMusicButton,
      'youtube',
      'yt music',
      'connect',
      'login',
    ], _buildYTMusicConnectCard()),
    _TaggedSection([
      context.l10n.appearance,
      context.l10n.theme,
      context.l10n.language,
      context.l10n.dynamicColorsNote,
      'appearance',
      'theme',
      'dark',
      'light',
      'mode',
    ], _buildAppearanceSection()),
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
    ], _buildQuickActions()),
    _TaggedSection([
      context.l10n.appInfo,
      context.l10n.settings,
      'app',
      'info',
      'ota',
      'patch',
      'version',
      'update',
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
    ], _buildGoogleAccountSection(ytMusicAuth: authState)),
    _TaggedSection([
      context.l10n.appearance,
      context.l10n.theme,
      context.l10n.language,
      context.l10n.dynamicColorsNote,
      'appearance',
      'theme',
      'dark',
      'light',
      'mode',
    ], _buildAppearanceSection()),
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
      'backup',
      'restore',
    ], _buildQuickActions()),
    _TaggedSection([
      context.l10n.sync,
      context.l10n.syncNow,
      context.l10n.library,
      'sync',
      'refresh',
      'library',
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
    ], _buildLibraryStats()),
    _TaggedSection([
      context.l10n.streamingCache,
      context.l10n.cleanUp,
      context.l10n.clearCache,
      'cache',
      'storage',
      'cleanup',
      'clear',
    ], _buildCacheSection()),
    _TaggedSection([
      context.l10n.analytics,
      'analytics',
      'hits',
      'misses',
      'network',
      'stats',
    ], _buildAnalyticsSection()),
    _TaggedSection([
      context.l10n.appInfo,
      context.l10n.settings,
      'app',
      'info',
      'ota',
      'patch',
      'version',
      'update',
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
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
            l10n.connectYoutubeMusic,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.connectYoutubeMusicSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _login,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(l10n.connectYtMusicButton),
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

        const SizedBox(height: 14),

        // Dynamic color note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Iconsax.colorfilter, size: 18, color: _accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.dynamicColorsNote,
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
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
      ],
    );
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

  Widget _buildGoogleAccountSection({YTMusicAuthState? ytMusicAuth}) {
    final googleAuthState = ref.watch(googleAuthStateProvider);
    final l10n = context.l10n;

    return _sectionCard(
      children: [
        _sectionHeader(l10n.yourProfile, Iconsax.user),
        const SizedBox(height: 16),
        if (googleAuthState.isLoading)
          Center(
            child: CircularProgressIndicator(
              color: _accentColor,
              strokeWidth: 2,
            ),
          )
        else if (googleAuthState.isSignedIn && googleAuthState.user != null)
          _buildGoogleSignedInRow(googleAuthState.user!)
        else
          _buildGoogleSignInButton(),
        // YT Music connected status (only show when logged in)
        if (ytMusicAuth != null && ytMusicAuth.isLoggedIn) ...[
          const SizedBox(height: 16),
          _buildYTMusicConnectedRow(ytMusicAuth),
        ],
      ],
    );
  }

  Widget _buildYTMusicConnectedRow(YTMusicAuthState authState) {
    final l10n = context.l10n;
    final connectedColor = _isDark
        ? _accentColor
        : HSLColor.fromColor(_accentColor).withLightness(0.3).toColor();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark
            ? _accentColor.withValues(alpha: 0.08)
            : _accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accentColor, _accentColor.withValues(alpha: 0.7)],
              ),
              shape: BoxShape.circle,
            ),
            child: authState.account?.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      authState.account!.avatarUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(Iconsax.music, color: _colors.onPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.youtubeMusicLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  authState.account?.name ?? l10n.connected,
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.connected,
              style: TextStyle(
                color: connectedColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleSignedInRow(GoogleUserProfile user) {
    final l10n = context.l10n;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: user.photoUrl == null
                ? LinearGradient(
                    colors: [_accentColor, _accentColor.withValues(alpha: 0.6)],
                  )
                : null,
          ),
          child: ClipOval(
            child: user.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: user.photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Center(
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          color: _colors.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Center(
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          color: _colors.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      user.initials,
                      style: TextStyle(
                        color: _colors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? l10n.googleUser,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              if (user.email != null)
                Text(
                  user.email!,
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.jamsAndProfile,
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
        IconButton(
          onPressed: () async {
            await ref.read(googleAuthStateProvider.notifier).signOut();
          },
          icon: Icon(Iconsax.logout, color: _textTertiary, size: 20),
          tooltip: context.l10n.signOut,
        ),
      ],
    );
  }

  Widget _buildGoogleSignInButton() {
    final l10n = context.l10n;
    return Column(
      children: [
        Text(
          l10n.signInGoogleProfilePictureJams,
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await ref.read(googleAuthStateProvider.notifier).signIn();
            },
            icon: Image.network(
              'https://www.google.com/favicon.ico',
              width: 18,
              height: 18,
              errorBuilder: (_, _, _) => const Icon(Icons.person, size: 18),
            ),
            label: Text(l10n.signInWithGoogle),
            style: OutlinedButton.styleFrom(
              foregroundColor: _textPrimary,
              side: BorderSide(
                color: _isDark ? InzxColors.darkBorder : InzxColors.border,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
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
                        content: Text(l10n.cacheCleanupComplete),
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
                          content: Text(l10n.cacheCleared),
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
                  content: Text(l10n.analyticsReset),
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
    final subscribedArtists = ref.watch(ytMusicSubscribedArtistsProvider);

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

  Widget _buildOtaDebugSection() {
    final l10n = context.l10n;
    final updater = ShorebirdUpdater();

    return _sectionCard(
      children: [
        _sectionHeader(l10n.appInfo, Iconsax.info_circle),
        const SizedBox(height: 12),
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
      ref.invalidate(ytMusicSubscribedArtistsProvider);
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
      ref.invalidate(ytMusicSubscribedArtistsProvider);
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

/// A deep-link searchable item that navigates to a specific screen.
class _SearchableItem {
  final List<String> tags;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget screen;

  List<String> get searchTerms => [...tags, title, subtitle];

  const _SearchableItem({
    required this.tags,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.screen,
  });
}
