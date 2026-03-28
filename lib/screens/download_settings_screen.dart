import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/design_system/design_system.dart';
import '../providers/providers.dart';
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
          _DownloadQualitySetting(isDark: isDark, accentColor: accentColor),

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
          _buildDataUsageInfo(context, isDark, accentColor),

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
  ) {
    final l10n = context.l10n;
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
            l10n.qualityLowChip,
            l10n.approxMegabytesValue('3'),
            isDark,
          ),
          _buildDataRow(
            l10n.qualityMediumChip,
            l10n.approxMegabytesValue('6'),
            isDark,
          ),
          _buildDataRow(
            l10n.qualityHighChip,
            l10n.approxMegabytesValue('12'),
            isDark,
          ),
          _buildDataRow(
            l10n.qualityMaxChip,
            l10n.approxMegabytesValue('25+'),
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
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : InzxColors.textSecondary,
            ),
          ),
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

/// Download quality setting widget
class _DownloadQualitySetting extends ConsumerWidget {
  final bool isDark;
  final Color accentColor;

  const _DownloadQualitySetting({
    required this.isDark,
    required this.accentColor,
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
                l10n.approxKbpsValue('64'),
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.medium,
                l10n.qualityMediumChip,
                l10n.approxKbpsValue('128'),
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.high,
                l10n.qualityHighChip,
                l10n.approxKbpsValue('256'),
                downloadQuality,
              ),
              _buildQualityChip(
                context,
                ref,
                AudioQuality.max,
                l10n.qualityMaxChip,
                l10n.qualityHighest,
                downloadQuality,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getQualityDescription(BuildContext context, AudioQuality quality) {
    final l10n = context.l10n;
    switch (quality) {
      case AudioQuality.auto:
        return l10n.qualityDescriptionAuto;
      case AudioQuality.low:
        return l10n.qualityDescriptionLow;
      case AudioQuality.medium:
        return l10n.qualityDescriptionMedium;
      case AudioQuality.high:
        return l10n.qualityDescriptionHigh;
      case AudioQuality.max:
        return l10n.qualityDescriptionMax;
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
            children: [
              Icon(Iconsax.folder_2, color: accentColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.storageLocation,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    downloadPathAsync.when(
                      data: (path) => Text(
                        path,
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
            l10n.privateStorageDownloadsNote,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : InzxColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
