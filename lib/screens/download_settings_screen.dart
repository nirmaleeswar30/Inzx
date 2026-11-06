import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../services/addons/addon_models.dart';
import '../services/addons/addon_service.dart';
import '../services/playback/playback_data.dart';
import '../services/download_service.dart';

/// Download settings screen — quality, location, and data usage
class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final jioSaavnEnabled = ref.watch(jioSaavnEnabledProvider);

    // Dynamic colors - plain white background in light mode
    final backgroundColor = (hasAlbumColors && isDark)
        ? albumColors.backgroundSecondary
        : (isDark ? InzxColors.darkBackground : InzxColors.background);
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(l10n.downloadSettingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Download quality section
          Text(
            l10n.downloadQuality,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.downloadQualitySubtitle,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Download quality selector
          ListenableBuilder(
            listenable: AddonService.instance,
            builder: (context, _) => _DownloadQualitySetting(
              isDark: isDark,
              accentColor: accentColor,
              jioSaavnEnabled: jioSaavnEnabled,
            ),
          ),

          const SizedBox(height: 32),

          // Download Location section
          Text(
            l10n.downloadLocation,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.downloadLocationSubtitleLong,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          _DownloadPathSetting(isDark: isDark, accentColor: accentColor),

          const SizedBox(height: 32),

          // Data usage info
          ListenableBuilder(
            listenable: AddonService.instance,
            builder: (context, _) => _buildDataUsageInfo(
              context,
              isDark,
              accentColor,
              jioSaavnEnabled,
            ),
          ),

          const SizedBox(height: 32),

          // Tip card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Iconsax.lamp_charge, color: accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.offlineDownloadTip,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : InzxColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataUsageInfo(
    BuildContext context,
    bool isDark,
    Color accentColor,
    bool jioSaavnEnabled,
  ) {
    final l10n = context.l10n;
    final lossless = _LosslessTier.current();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
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
              Icon(
                Iconsax.info_circle,
                size: 18,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.estimatedStoragePerSong,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDataRow(
            '${l10n.qualityLowChip} (~48–64 kbps)',
            '~1.5 – 2 MB',
            isDark,
          ),
          _buildDataRow(
            '${l10n.qualityMediumChip} (~70–128 kbps)',
            '~3 – 4 MB',
            isDark,
          ),
          _buildDataRow(
            '${l10n.qualityHighChip} (${jioSaavnEnabled ? '~160–320 kbps' : '~160 kbps'})',
            jioSaavnEnabled ? '~4 – 8 MB' : '~4 – 5 MB',
            isDark,
          ),
          _buildDataRow(
            '${l10n.qualityMaxChip} (${lossless?.bitrate ?? (jioSaavnEnabled ? '320 kbps' : '~160 kbps')})',
            lossless?.storage ?? (jioSaavnEnabled ? '~8 – 10 MB' : '~4 – 5 MB'),
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : InzxColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What Max means for downloads with the lossless addons as they're set up:
/// its numbers come from the enabled addons' quality tier.
class _LosslessTier {
  const _LosslessTier({
    required this.chip,
    required this.description,
    required this.bitrate,
    required this.storage,
  });

  final String chip;
  final String description;
  final String bitrate;
  final String storage;

  /// Null when no addon is enabled, so Max tops out at the best lossy copy.
  static _LosslessTier? current() {
    final enabled = AddonService.instance.addons.where((a) => a.enabled);
    if (enabled.isEmpty) return null;
    if (enabled.any((a) => a.quality == AddonQuality.hiRes)) {
      return const _LosslessTier(
        chip: 'Hi-Res FLAC',
        description: 'Hi-Res FLAC, up to 24-bit / 192 kHz,',
        bitrate: 'Hi-Res FLAC, ~700–5000 kbps',
        storage: '~20 – 150 MB',
      );
    }
    return const _LosslessTier(
      chip: 'FLAC',
      description: 'Lossless FLAC, 16-bit / 44.1 kHz,',
      bitrate: 'FLAC, ~700–1100 kbps',
      storage: '~20 – 35 MB',
    );
  }
}

/// Download quality setting widget
class _DownloadQualitySetting extends ConsumerWidget {
  final bool isDark;
  final Color accentColor;
  final bool jioSaavnEnabled;

  const _DownloadQualitySetting({
    required this.isDark,
    required this.accentColor,
    required this.jioSaavnEnabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadQuality = ref.watch(downloadQualityProvider);
    final l10n = context.l10n;

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
              Icon(Iconsax.document_download, color: accentColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.downloadQuality,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getQualityDescription(context, downloadQuality),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : InzxColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Quality options as chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQualityChip(
                context,
                ref,
                AudioQuality.low,
                l10n.qualityLowChip,
                '~48–64 kbps',
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.medium,
                l10n.qualityMediumChip,
                '~70–128 kbps',
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.high,
                l10n.qualityHighChip,
                jioSaavnEnabled ? '~160–320 kbps' : '~160 kbps',
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.max,
                l10n.qualityMaxChip,
                _LosslessTier.current()?.chip ??
                    (jioSaavnEnabled ? 'Up to 320 kbps' : '~160 kbps'),
                downloadQuality,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getQualityDescription(BuildContext context, AudioQuality quality) {
    switch (quality) {
      case AudioQuality.auto:
        return 'Automatic quality based on connection';
      case AudioQuality.low:
        return 'Saves storage & data (~48–64 kbps)';
      case AudioQuality.medium:
        return 'Standard quality (~70–128 kbps)';
      case AudioQuality.high:
        return jioSaavnEnabled
            ? 'High fidelity (~160–320 kbps with JioSaavn)'
            : 'Best standard quality (~160 kbps YouTube)';
      case AudioQuality.max:
        final bestLossy = jioSaavnEnabled
            ? 'up to 320 kbps (JioSaavn) or ~160 kbps Opus'
            : '~160 kbps Opus';
        final lossless = _LosslessTier.current();
        return lossless != null
            ? '${lossless.description} when found, else best lossy ($bestLossy)'
            : 'Best lossy ($bestLossy) • Lossless with an addon';
    }
  }

  Widget _buildQualityChip(
    BuildContext context,
    WidgetRef ref,
    AudioQuality quality,
    String label,
    String subtitle,
    AudioQuality currentQuality,
  ) {
    final isSelected = quality == currentQuality;

    return FilterChip(
      selected: isSelected,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? InzxColors.contrastTextOn(
                      accentColor,
                    ).withValues(alpha: 0.8)
                  : (isDark ? Colors.white54 : Colors.grey),
            ),
          ),
        ],
      ),
      selectedColor: accentColor,
      checkmarkColor: InzxColors.contrastTextOn(accentColor),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected
            ? InzxColors.contrastTextOn(accentColor)
            : (isDark ? Colors.white : Colors.black87),
      ),
      onSelected: (selected) {
        if (selected) {
          ref.read(downloadQualityProvider.notifier).setQuality(quality);
          ref
              .read(downloadManagerProvider.notifier)
              .setDownloadQuality(quality);
        }
      },
    );
  }
}

/// Download path setting widget
class _DownloadPathSetting extends ConsumerWidget {
  final bool isDark;
  final Color accentColor;

  const _DownloadPathSetting({required this.isDark, required this.accentColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadPathAsync = ref.watch(downloadPathProvider);
    final l10n = context.l10n;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Iconsax.folder_2, color: accentColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.storageLocation,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : InzxColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        downloadPathAsync.maybeWhen(
                          data: (info) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: info.isCustom
                                  ? accentColor.withValues(alpha: 0.2)
                                  : (isDark
                                      ? Colors.white12
                                      : Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              info.isCustom ? 'Custom' : 'Default',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: info.isCustom
                                    ? accentColor
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black54),
                              ),
                            ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    downloadPathAsync.when(
                      data: (info) => Text(
                        info.path,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : InzxColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      loading: () => Text(
                        l10n.loading,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : InzxColors.textSecondary,
                        ),
                      ),
                      error: (error, stackTrace) => Text(
                        l10n.errorLoadingPath,
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
          const SizedBox(height: 12),
          Text(
            downloadPathAsync.maybeWhen(
              data: (info) => info.isCustom
                  ? 'Tracks are saved directly to your selected directory and can be accessed by media players and file managers.'
                  : l10n.privateStorageDownloadsNote,
              orElse: () => l10n.privateStorageDownloadsNote,
            ),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : InzxColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final selected = await FilePicker.platform.getDirectoryPath(
                    dialogTitle: 'Select Download Folder',
                  );
                  if (selected != null && selected.trim().isNotEmpty) {
                    await ref
                        .read(downloadPathProvider.notifier)
                        .setCustomPath(selected.trim());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Download storage location updated'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Iconsax.folder_add, size: 16),
                label: const Text(
                  'Change Location',
                  style: TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: InzxColors.contrastTextOn(accentColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              downloadPathAsync.maybeWhen(
                data: (info) => info.isCustom
                    ? TextButton.icon(
                        onPressed: () async {
                          await ref
                              .read(downloadPathProvider.notifier)
                              .setCustomPath(null);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Storage location reset to default app storage',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text(
                          'Reset to Default',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.black87,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
