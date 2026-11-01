import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/design_system/design_system.dart';
import '../core/l10n/app_localizations_x.dart';
import '../../core/providers/theme_provider.dart';
import '../providers/providers.dart';
import '../services/playback/playback_data.dart';
import 'widgets/addon_source_card.dart';
import 'widgets/audio_output_card.dart';
import 'widgets/automix_settings_card.dart';
import '../services/automix/automix_service.dart';
import 'equalizer_screen.dart';
import 'auto_eq_screen.dart';
import '../services/addons/addon_service.dart';

/// Audio settings screen with quality selection
class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;

    // Dynamic colors - plain white background in light mode
    final backgroundColor = (hasAlbumColors && isDark)
        ? albumColors.backgroundSecondary
        : (isDark ? InzxColors.darkBackground : InzxColors.background);
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    final currentQuality = ref.watch(audioQualityProvider);
    final streamInfo = ref.watch(streamQualityInfoProvider);
    final streamCacheWifiOnly = ref.watch(streamCacheWifiOnlyProvider);
    final streamCacheLimitMb = ref.watch(streamCacheSizeLimitMbProvider);
    final streamCacheMaxConcurrent = ref.watch(
      streamCacheMaxConcurrentProvider,
    );
    final crossfadeDurationMs = ref.watch(crossfadeDurationMsProvider);
    final streamCacheUsageAsync = ref.watch(streamAudioCacheUsageBytesProvider);
    final jioSaavnEnabled = ref.watch(jioSaavnEnabledProvider);
    final preferAudioVersions = ref.watch(preferAudioVersionsProvider);
    final showSmartAudioRouting = ref.watch(showSmartAudioRoutingProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(l10n.audioSettingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current quality info
          if (streamInfo.isNotEmpty)
            _buildInfoCard(
              context,
              isDark: isDark,
              accentColor: accentColor,
              title: l10n.nowPlayingLabel,
              subtitle: streamInfo,
              icon: Iconsax.music_circle,
            ),

          const SizedBox(height: 24),

          // Quality section header
          Text(
            l10n.streamingQuality,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.higherQualityUsesMoreData,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),

          const SizedBox(height: 16),

          // Quality options. What each one does (see the player's
          // _qualityAllowsLossless): Low/Medium are YouTube only, High is
          // the best lossy copy, Max adds lossless, Auto is Max on Wi-Fi
          // and lighter on mobile data.
          ListenableBuilder(
            listenable: AddonService.instance,
            builder: (context, _) {
              final hasLossless = AddonService.instance.isEnabled;
              final bestLossy = jioSaavnEnabled
                  ? 'up to 320 kbps (JioSaavn) or ~160 kbps Opus'
                  : '~160 kbps Opus';
              return Column(
                children: [
                  _buildQualityOption(
                    context,
                    ref: ref,
                    isDark: isDark,
                    accentColor: accentColor,
                    quality: AudioQuality.auto,
                    currentQuality: currentQuality,
                    title: l10n.qualityAutoChip,
                    subtitle: hasLossless
                        ? 'Wi-Fi: lossless FLAC • Mobile data: lossy, lighter'
                        : 'Wi-Fi: best quality • Mobile data: lighter',
                    icon: Iconsax.autobrightness,
                    onTap: () =>
                        playerService.setAudioQuality(AudioQuality.auto),
                  ),
                  _buildQualityOption(
                    context,
                    ref: ref,
                    isDark: isDark,
                    accentColor: accentColor,
                    quality: AudioQuality.low,
                    currentQuality: currentQuality,
                    title: l10n.qualityLowChip,
                    subtitle: '~48–64 kbps • Data saver, YouTube only',
                    icon: Iconsax.volume_low,
                    onTap: () =>
                        playerService.setAudioQuality(AudioQuality.low),
                  ),
                  _buildQualityOption(
                    context,
                    ref: ref,
                    isDark: isDark,
                    accentColor: accentColor,
                    quality: AudioQuality.medium,
                    currentQuality: currentQuality,
                    title: l10n.qualityMediumChip,
                    subtitle: '~70–128 kbps • Balanced, YouTube only',
                    icon: Iconsax.volume_high,
                    onTap: () =>
                        playerService.setAudioQuality(AudioQuality.medium),
                  ),
                  _buildQualityOption(
                    context,
                    ref: ref,
                    isDark: isDark,
                    accentColor: accentColor,
                    quality: AudioQuality.high,
                    currentQuality: currentQuality,
                    title: l10n.qualityHighChip,
                    subtitle: 'Best lossy: $bestLossy',
                    icon: Iconsax.headphones,
                    onTap: () =>
                        playerService.setAudioQuality(AudioQuality.high),
                  ),
                  _buildQualityOption(
                    context,
                    ref: ref,
                    isDark: isDark,
                    accentColor: accentColor,
                    quality: AudioQuality.max,
                    currentQuality: currentQuality,
                    title: l10n.qualityMaxChip,
                    subtitle: hasLossless
                        ? 'Lossless / Hi-Res FLAC when found, else best lossy'
                        : 'Best lossy ($bestLossy) • Lossless with an addon',
                    icon: Iconsax.sound,
                    recommended: true,
                    onTap: () =>
                        playerService.setAudioQuality(AudioQuality.max),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // JioSaavn source section
          Text(
            'High Quality Sources',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable external studio-quality sources for matching tracks',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _buildJioSaavnSection(
            context: context,
            isDark: isDark,
            accentColor: accentColor,
            jioSaavnEnabled: jioSaavnEnabled,
            onChanged: (enabled) async {
              await playerService.setJioSaavnEnabled(enabled);
            },
          ),
          const SizedBox(height: 12),
          AddonSourceCard(
            isDark: isDark,
            accentColor: accentColor,
            switchBuilder: (value, onChanged) => _buildCustomSwitch(
              value: value,
              accentColor: accentColor,
              isDark: isDark,
              onChanged: onChanged,
            ),
          ),

          const SizedBox(height: 32),
          Text(
            l10n.crossfadeTransition,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.blendTrackEndsIntoNext,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Automix decides its own length from each pair of tracks, so the
          // slider only shows while Automix is off (as in BitChord).
          ListenableBuilder(
            listenable: AutomixService.instance,
            builder: (context, _) => AutomixService.instance.enabled
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildCrossfadeSection(
                      context: context,
                      isDark: isDark,
                      accentColor: accentColor,
                      currentDurationMs: crossfadeDurationMs,
                      onChanged: (value) async {
                        await playerService.setCrossfadeDurationMs(value);
                      },
                    ),
                  ),
          ),
          AutomixSettingsCard(
            isDark: isDark,
            accentColor: accentColor,
            switchBuilder: (value, onChanged) => _buildCustomSwitch(
              value: value,
              accentColor: accentColor,
              isDark: isDark,
              onChanged: onChanged,
            ),
          ),

          const SizedBox(height: 32),

          // Output: hi-res and bit-perfect USB DAC
          Text(
            'Output',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How lossless audio leaves the app',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AudioOutputCard(
            isDark: isDark,
            accentColor: accentColor,
            switchBuilder: (value, onChanged) => _buildCustomSwitch(
              value: value,
              accentColor: accentColor,
              isDark: isDark,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 12),
          _buildNavCard(
            isDark: isDark,
            accentColor: accentColor,
            icon: Iconsax.setting_4,
            title: 'Equalizer',
            subtitle: '7 bands with presets',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EqualizerScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildNavCard(
            isDark: isDark,
            accentColor: accentColor,
            icon: Iconsax.headphone,
            title: 'AutoEQ',
            subtitle: 'Correct your headphones with the AutoEQ database',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AutoEqScreen()),
            ),
          ),

          const SizedBox(height: 32),

          // Streaming cache section
          Text(
            l10n.streamingCache,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.preCachesNextTracks,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _buildStreamingCacheSection(
            context,
            ref: ref,
            isDark: isDark,
            accentColor: accentColor,
            wifiOnly: streamCacheWifiOnly,
            cacheLimitMb: streamCacheLimitMb,
            maxConcurrent: streamCacheMaxConcurrent,
            usageAsync: streamCacheUsageAsync,
            onWifiOnlyChanged: (enabled) async {
              await playerService.setStreamCacheWifiOnly(enabled);
              ref.read(streamAudioCacheRefreshProvider.notifier).state++;
            },
            onCacheLimitChanged: (limitMb) async {
              await playerService.setStreamCacheSizeLimitMb(limitMb);
              ref.read(streamAudioCacheRefreshProvider.notifier).state++;
            },
            onMaxConcurrentChanged: (value) async {
              await playerService.setStreamCacheMaxConcurrent(value);
            },
          ),

          const SizedBox(height: 32),

          // Playback behavior section
          Text(
            l10n.playback,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.playbackSectionSubtitle,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _buildToggleTile(
            isDark: isDark,
            accentColor: accentColor,
            icon: Iconsax.music,
            title: l10n.preferAudioVersions,
            subtitle: l10n.preferAudioVersionsSubtitle,
            value: preferAudioVersions,
            onChanged: (val) =>
                ref.read(preferAudioVersionsProvider.notifier).setEnabled(val),
          ),
          const SizedBox(height: 12),
          _buildToggleTile(
            isDark: isDark,
            accentColor: accentColor,
            icon: Iconsax.volume_high,
            title: l10n.smartAudioRouting,
            subtitle: l10n.smartAudioRoutingSubtitle,
            value: showSmartAudioRouting,
            onChanged: (val) => ref
                .read(showSmartAudioRoutingProvider.notifier)
                .setEnabled(val),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required bool isDark,
    required Color accentColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value
                  ? accentColor.withValues(alpha: 0.2)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: value
                  ? accentColor
                  : (isDark ? Colors.white54 : Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : InzxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _buildCustomSwitch(
            value: value,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// A card that opens another screen, styled like the switch cards.
  Widget _buildNavCard({
    required bool isDark,
    required Color accentColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white12 : accentColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : InzxColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white38 : InzxColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSwitch({
    required bool value,
    required Color accentColor,
    required bool isDark,
    // Null shows the switch disabled.
    required ValueChanged<bool>? onChanged,
  }) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: accentColor,
      inactiveThumbColor: isDark ? Colors.white70 : Colors.white,
      inactiveTrackColor: isDark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.grey.shade300,
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      trackOutlineWidth: WidgetStateProperty.all(0.0),
    );
  }

  Widget _buildJioSaavnSection({
    required BuildContext context,
    required bool isDark,
    required Color accentColor,
    required bool jioSaavnEnabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: jioSaavnEnabled
                  ? accentColor.withValues(alpha: 0.2)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Opacity(
                opacity: jioSaavnEnabled ? 1.0 : 0.4,
                child: Image.asset(
                  'assets/icon/JioSaavn.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      Iconsax.music_dashboard,
                      color: jioSaavnEnabled
                          ? accentColor
                          : (isDark ? Colors.white54 : Colors.grey.shade600),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JioSaavn',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : InzxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stream in 320 kbps studio quality',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _buildCustomSwitch(
            value: jioSaavnEnabled,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }


  Widget _buildInfoCard(
    BuildContext context, {
    required bool isDark,
    required Color accentColor,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : accentColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : InzxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityOption(
    BuildContext context, {
    required WidgetRef ref,
    required bool isDark,
    required Color accentColor,
    required AudioQuality quality,
    required AudioQuality currentQuality,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
    required VoidCallback onTap,
  }) {
    final isSelected = quality == currentQuality;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accentColor
                : isDark
                ? Colors.white12
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.2)
                    : isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white54 : Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : InzxColors.textPrimary,
                        ),
                      ),
                      if (recommended)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            context.l10n.recommended,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : InzxColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: accentColor)
            else
              Icon(
                Icons.circle_outlined,
                color: isDark ? Colors.white24 : Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingCacheSection(
    BuildContext context, {
    required WidgetRef ref,
    required bool isDark,
    required Color accentColor,
    required bool wifiOnly,
    required int cacheLimitMb,
    required int maxConcurrent,
    required AsyncValue<int> usageAsync,
    required Future<void> Function(bool enabled) onWifiOnlyChanged,
    required Future<void> Function(int limitMb) onCacheLimitChanged,
    required Future<void> Function(int value) onMaxConcurrentChanged,
  }) {
    const cacheLimitOptions = [256, 512, 1024, 2048, 4096];
    const concurrencyOptions = [1, 2, 3, 4];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.archive, color: accentColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.smartStreamCache,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    usageAsync.when(
                      data: (bytes) => Text(
                        context.l10n.usedCacheStorage(
                          _formatCacheSize(context, bytes),
                          cacheLimitMb,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : InzxColors.textSecondary,
                        ),
                      ),
                      loading: () => Text(
                        context.l10n.calculatingCacheUsage,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : InzxColors.textSecondary,
                        ),
                      ),
                      error: (error, stackTrace) => Text(
                        context.l10n.unableToReadCacheUsage,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.preCacheNetwork,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: wifiOnly,
                label: Text(context.l10n.wifiOnly),
                selectedColor: accentColor,
                labelStyle: TextStyle(
                  color: wifiOnly
                      ? InzxColors.contrastTextOn(accentColor)
                      : (isDark ? Colors.white : InzxColors.textPrimary),
                ),
                onSelected: (picked) {
                  if (picked) {
                    onWifiOnlyChanged(true);
                  }
                },
              ),
              ChoiceChip(
                selected: !wifiOnly,
                label: Text(context.l10n.wifiAndMobileData),
                selectedColor: accentColor,
                labelStyle: TextStyle(
                  color: !wifiOnly
                      ? InzxColors.contrastTextOn(accentColor)
                      : (isDark ? Colors.white : InzxColors.textPrimary),
                ),
                onSelected: (picked) {
                  if (picked) {
                    onWifiOnlyChanged(false);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            wifiOnly
                ? context.l10n.preCacheRunsWifiOnly
                : context.l10n.preCacheRunsWifiAndMobile,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.concurrentPreCacheDownloads,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: concurrencyOptions.map((option) {
              final selected = option == maxConcurrent;
              return ChoiceChip(
                selected: selected,
                label: Text(option.toString()),
                selectedColor: accentColor,
                labelStyle: TextStyle(
                  color: selected
                      ? InzxColors.contrastTextOn(accentColor)
                      : (isDark ? Colors.white : InzxColors.textPrimary),
                ),
                onSelected: (picked) {
                  if (picked) {
                    onMaxConcurrentChanged(option);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.higherValuesCacheFaster,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.cacheSizeLimit,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cacheLimitOptions.map((optionMb) {
              final selected = optionMb == cacheLimitMb;
              return ChoiceChip(
                selected: selected,
                label: Text(context.l10n.megabytesValue(optionMb.toString())),
                selectedColor: accentColor,
                labelStyle: TextStyle(
                  color: selected
                      ? InzxColors.contrastTextOn(accentColor)
                      : (isDark ? Colors.white : InzxColors.textPrimary),
                ),
                onSelected: (picked) {
                  if (picked) {
                    onCacheLimitChanged(optionMb);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCrossfadeSection({
    required BuildContext context,
    required bool isDark,
    required Color accentColor,
    required int currentDurationMs,
    required Future<void> Function(int value) onChanged,
  }) {
    const optionsMs = [0, 5000, 8000, 10000, 12000];

    String labelFor(int ms) {
      if (ms == 0) return context.l10n.off;
      return context.l10n.secondsShort(
        (ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: optionsMs.map((optionMs) {
              final selected = optionMs == currentDurationMs;
              return ChoiceChip(
                selected: selected,
                label: Text(labelFor(optionMs)),
                selectedColor: accentColor,
                labelStyle: TextStyle(
                  color: selected
                      ? InzxColors.contrastTextOn(accentColor)
                      : (isDark ? Colors.white : InzxColors.textPrimary),
                ),
                onSelected: (picked) {
                  if (picked) {
                    onChanged(optionMs);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            currentDurationMs == 0
                ? context.l10n.crossfadeDisabled
                : context.l10n.currentValueLabel(labelFor(currentDurationMs)),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCacheSize(BuildContext context, int bytes) {
    const mb = 1024 * 1024;
    if (bytes <= 0) return context.l10n.megabytesValue('0');
    return context.l10n.megabytesValue((bytes / mb).toStringAsFixed(1));
  }
}

/// Quick quality picker for Now Playing screen
class AudioQualityPicker extends ConsumerWidget {
  const AudioQualityPicker({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const AudioQualityPicker(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    final currentQuality = ref.watch(audioQualityProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
              color: isDark ? Colors.white30 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.l10n.audioQuality,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : InzxColors.textPrimary,
              ),
            ),
          ),

          const Divider(height: 1),

          _buildQuickOption(
            context,
            context.l10n.qualityAutoChip,
            AudioQuality.auto,
            currentQuality,
            isDark,
            accentColor,
            () {
              playerService.setAudioQuality(AudioQuality.auto);
              Navigator.pop(context);
            },
          ),
          _buildQuickOption(
            context,
            context.l10n.qualityLowKbps,
            AudioQuality.low,
            currentQuality,
            isDark,
            accentColor,
            () {
              playerService.setAudioQuality(AudioQuality.low);
              Navigator.pop(context);
            },
          ),
          _buildQuickOption(
            context,
            context.l10n.qualityMediumKbps,
            AudioQuality.medium,
            currentQuality,
            isDark,
            accentColor,
            () {
              playerService.setAudioQuality(AudioQuality.medium);
              Navigator.pop(context);
            },
          ),
          _buildQuickOption(
            context,
            context.l10n.qualityHighKbps,
            AudioQuality.high,
            currentQuality,
            isDark,
            accentColor,
            () {
              playerService.setAudioQuality(AudioQuality.high);
              Navigator.pop(context);
            },
          ),
          _buildQuickOption(
            context,
            context.l10n.qualityMaximumKbps,
            AudioQuality.max,
            currentQuality,
            isDark,
            accentColor,
            () {
              playerService.setAudioQuality(AudioQuality.max);
              Navigator.pop(context);
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickOption(
    BuildContext context,
    String title,
    AudioQuality quality,
    AudioQuality current,
    bool isDark,
    Color accentColor,
    VoidCallback onTap,
  ) {
    final isSelected = quality == current;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.circle_outlined,
          color: isSelected
              ? accentColor
              : (isDark ? Colors.white38 : Colors.grey),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : InzxColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
