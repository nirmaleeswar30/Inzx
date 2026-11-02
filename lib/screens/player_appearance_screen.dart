import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../core/l10n/app_localizations_x.dart';
import '../../core/providers/theme_provider.dart';
import '../providers/providers.dart';
import 'widgets/ai_lyrics_settings_sheet.dart';

/// Dedicated screen for Now Playing / player appearance options.
///
/// Split out of the main settings "Appearance" section so that the many
/// player-related visual toggles live in one focused place instead of a single
/// oversized card. Reached from Settings → Appearance → "Player & Now Playing".
class PlayerAppearanceScreen extends ConsumerStatefulWidget {
  const PlayerAppearanceScreen({super.key});

  @override
  ConsumerState<PlayerAppearanceScreen> createState() =>
      _PlayerAppearanceScreenState();
}

class _PlayerAppearanceScreenState
    extends ConsumerState<PlayerAppearanceScreen> {
  // ── Theme helpers (mirrors YTMusicSettingsScreen) ──────────────────
  ColorScheme get _colors => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  AlbumColors get _albumColors => ref.watch(albumColorsProvider);
  bool get _hasAlbumColors => !_albumColors.isDefault;

  Color get _backgroundColor {
    if (_hasAlbumColors && _isDark) {
      return _albumColors.backgroundSecondary;
    }
    return _isDark ? InzxColors.darkBackground : InzxColors.background;
  }

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

  Widget get _divider => Divider(
        height: 1,
        color: _isDark ? InzxColors.darkDivider : InzxColors.divider,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(l10n.playerAndNowPlaying),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: _textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Layout & style ────────────────────────────────────────
          _sectionCard(
            children: [
              _sectionHeader(l10n.layoutAndStyle, Icons.art_track_rounded),
              const SizedBox(height: 4),
              _settingsTile(
                icon: Icons.art_track_rounded,
                iconBg: _accentColor,
                title: l10n.nowPlayingStyle,
                subtitle:
                    '${getNowPlayingStyleName(ref.watch(nowPlayingStyleProvider))} • ${getNowPlayingStyleDescription(ref.watch(nowPlayingStyleProvider))}',
                onTap: _showNowPlayingStyleSelector,
              ),
              _divider,
              _settingsTile(
                icon: Icons.graphic_eq_rounded,
                iconBg: _accentColor,
                title: l10n.progressBarStyle,
                subtitle:
                    '${getProgressBarStyleName(ref.watch(progressBarStyleProvider))} • ${getProgressBarStyleDescription(ref.watch(progressBarStyleProvider))}',
                onTap: _showProgressBarStyleSelector,
              ),
              _divider,
              _switchTile(
                icon: Icons.water_drop_rounded,
                iconBg: _accentColor,
                title: l10n.liquidGlass,
                subtitle: l10n.liquidGlassSubtitle,
                value: ref.watch(liquidGlassNavProvider),
                onChanged: (val) =>
                    ref.read(liquidGlassNavProvider.notifier).setEnabled(val),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Album art ─────────────────────────────────────────────
          _sectionCard(
            children: [
              _sectionHeader(l10n.albumArt, Icons.play_circle_outline_rounded),
              const SizedBox(height: 4),
              _switchTile(
                icon: Icons.rotate_right_rounded,
                iconBg: _accentColor,
                title: l10n.rotatingMiniplayerArt,
                subtitle: l10n.rotatingMiniplayerArtSubtitle,
                value: ref.watch(rotatingMiniPlayerArtProvider),
                onChanged: (val) => ref
                    .read(rotatingMiniPlayerArtProvider.notifier)
                    .setEnabled(val),
              ),
              _divider,
              _switchTile(
                icon: Icons.play_circle_outline_rounded,
                iconBg: _accentColor,
                title: l10n.animatedAlbumArt,
                subtitle: l10n.animatedAlbumArtSubtitle,
                value: ref.watch(animatedAlbumArtProvider),
                onChanged: (val) =>
                    ref.read(animatedAlbumArtProvider.notifier).setEnabled(val),
              ),
              _divider,
              _switchTile(
                icon: Icons.blur_on_rounded,
                iconBg: _accentColor,
                title: l10n.ambientReflectionTitle,
                subtitle: l10n.ambientReflectionSubtitle,
                value: ref.watch(ambientReflectionsEnabledProvider),
                onChanged: (val) => ref
                    .read(ambientReflectionsEnabledProvider.notifier)
                    .setEnabled(val),
              ),
              if (ref.watch(ambientReflectionsEnabledProvider) &&
                  ref.watch(animatedAlbumArtProvider) &&
                  ref.watch(nowPlayingStyleProvider) == NowPlayingStyle.edge) ...[
                _divider,
                _switchTile(
                  icon: Icons.auto_awesome_rounded,
                  iconBg: _accentColor,
                  title: l10n.ambientReflectionCanvasTitle,
                  subtitle: l10n.ambientReflectionCanvasSubtitle,
                  value: ref.watch(cinematicAmbientOnlyForAnimatedArtProvider),
                  onChanged: (val) => ref
                      .read(cinematicAmbientOnlyForAnimatedArtProvider.notifier)
                      .toggle(),
                ),
              ],
              if (ref.watch(ambientReflectionsEnabledProvider) &&
                  ref.watch(animatedAlbumArtProvider) &&
                  ref.watch(nowPlayingStyleProvider) != NowPlayingStyle.edge) ...[
                _divider,
                _switchTile(
                  icon: Icons.blur_circular_rounded,
                  iconBg: _accentColor,
                  title: l10n.dynamicAmbientCanvasTitle,
                  subtitle: l10n.dynamicAmbientCanvasSubtitle,
                  value:
                      ref.watch(dynamicAmbientBackgroundForAnimatedArtProvider),
                  onChanged: (val) => ref
                      .read(dynamicAmbientBackgroundForAnimatedArtProvider
                          .notifier)
                      .toggle(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // ── Lyrics ────────────────────────────────────────────────
          _sectionCard(
            children: [
              _sectionHeader(l10n.lyrics, Iconsax.text),
              const SizedBox(height: 4),
              _switchTile(
                icon: Iconsax.text,
                iconBg: _accentColor,
                title: l10n.lyricsBelowAlbumArt,
                subtitle: l10n.lyricsBelowAlbumArtSubtitle,
                value: ref.watch(showLyricsBelowAlbumArtProvider),
                onChanged: (val) => ref
                    .read(showLyricsBelowAlbumArtProvider.notifier)
                    .setEnabled(val),
              ),
              _divider,
              _settingsTile(
                icon: Iconsax.translate,
                iconBg: _accentColor,
                title: l10n.aiLyricsTranslation,
                subtitle: l10n.aiLyricsTranslationSubtitle,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const AiLyricsSettingsSheet(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Reusable widgets ───────────────────────────────────────────────

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
        activeThumbColor: Colors.white,
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

  // ── Style selectors (moved from YTMusicSettingsScreen) ─────────────

  Future<void> _showNowPlayingStyleSelector() async {
    final currentStyle = ref.read(nowPlayingStyleProvider);
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.art_track_rounded,
                          size: 20,
                          color: _accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.l10n.nowPlayingStyle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...NowPlayingStyle.values.map((style) {
                    final isSelected = style == currentStyle;
                    final title = getNowPlayingStyleName(style);
                    final desc = getNowPlayingStyleDescription(style);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: isSelected
                            ? _accentColor.withValues(alpha: 0.12)
                            : (_isDark
                                ? const Color(0xFF141416)
                                : const Color(0xFFF5F5F7)),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            ref
                                .read(nowPlayingStyleProvider.notifier)
                                .setStyle(style);
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? _accentColor
                                    : (_isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : InzxColors.border
                                            .withValues(alpha: 0.3)),
                                width: isSelected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _accentColor.withValues(alpha: 0.22)
                                        : (_isDark
                                            ? Colors.white.withValues(alpha: 0.06)
                                            : Colors.black
                                                .withValues(alpha: 0.05)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    style == NowPlayingStyle.ripple
                                        ? Icons.filter_vintage_rounded
                                        : (style == NowPlayingStyle.edge
                                            ? Icons.splitscreen_rounded
                                            : (style == NowPlayingStyle.og
                                                ? Icons.view_headline_rounded
                                                : Icons.crop_square_rounded)),
                                    color: isSelected
                                        ? _accentColor
                                        : _textPrimary.withValues(alpha: 0.8),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? _accentColor
                                              : _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.3,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: _accentColor,
                                    size: 22,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showProgressBarStyleSelector() async {
    final currentStyle = ref.read(progressBarStyleProvider);
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 20,
                          color: _accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.l10n.progressBarStyle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...ProgressBarStyle.values.map((style) {
                    final isSelected = style == currentStyle;
                    final title = getProgressBarStyleName(style);
                    final desc = getProgressBarStyleDescription(style);

                    final IconData styleIcon;
                    switch (style) {
                      case ProgressBarStyle.defaultLinear:
                        styleIcon = Icons.linear_scale_rounded;
                        break;
                      case ProgressBarStyle.waveform:
                        styleIcon = Icons.waves_rounded;
                        break;
                      case ProgressBarStyle.spectrum:
                        styleIcon = Icons.graphic_eq_rounded;
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: isSelected
                            ? _accentColor.withValues(alpha: 0.12)
                            : (_isDark
                                ? const Color(0xFF141416)
                                : const Color(0xFFF5F5F7)),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            ref
                                .read(progressBarStyleProvider.notifier)
                                .setStyle(style);
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? _accentColor
                                    : (_isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : InzxColors.border
                                            .withValues(alpha: 0.3)),
                                width: isSelected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _accentColor.withValues(alpha: 0.22)
                                        : (_isDark
                                            ? Colors.white.withValues(alpha: 0.06)
                                            : Colors.black
                                                .withValues(alpha: 0.05)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    styleIcon,
                                    color: isSelected
                                        ? _accentColor
                                        : _textPrimary.withValues(alpha: 0.8),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? _accentColor
                                              : _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.3,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: _accentColor,
                                    size: 22,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
