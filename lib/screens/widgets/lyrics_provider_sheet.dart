import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';

class LyricsProviderSheet {
  static void show(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.read(albumColorsProvider);
    final accentColor = isDark ? albumColors.accentLight : albumColors.accent;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {        return Consumer(
          builder: (context, sheetRef, _) {
            final currentLyricsState = sheetRef.watch(lyricsProvider);
            final sheetBgColor = isDark
                ? const Color(0xFF141414).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.94);
            final textColor =
                isDark ? Colors.white : const Color(0xFF1A1A1A);
            final secondaryColor =
                isDark ? Colors.white60 : Colors.black54;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: sheetBgColor,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle
                          Container(
                            width: 42,
                            height: 4.5,
                            margin: const EdgeInsets.only(top: 14, bottom: 8),
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),

                          // Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.analytics_rounded,
                                    size: 22,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Lyrics Providers',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Stats for nerds • Switch active source',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: secondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: secondaryColor,
                                    size: 24,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: textColor.withValues(alpha: 0.05),
                                  ),
                                  onPressed: () => Navigator.pop(sheetContext),
                                ),
                              ],
                            ),
                          ),

                          // Provider List
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: providerNames.length,
                              itemBuilder: (context, index) {
                                final provider = providerNames[index];
                                final isCurrent =
                                    currentLyricsState.currentProvider == provider;
                                final status = currentLyricsState.providers[provider];
                                final data = status?.data;

                                // Compute status info
                                Widget leadingIcon;
                                String subtitleText;
                                Color subtitleColor;
                                Widget? trailingBadge;

                                if (status == null ||
                                    status.state == LyricsProviderState.idle) {
                                  leadingIcon = Icon(
                                    Icons.cloud_outlined,
                                    size: 20,
                                    color: secondaryColor.withValues(alpha: 0.5),
                                  );
                                  subtitleText = 'Tap to fetch';
                                  subtitleColor =
                                      secondaryColor.withValues(alpha: 0.6);
                                } else if (status.state ==
                                    LyricsProviderState.fetching) {
                                  leadingIcon = SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentColor,
                                    ),
                                  );
                                  subtitleText = 'Fetching lyrics...';
                                  subtitleColor = accentColor;
                                } else if (status.state ==
                                    LyricsProviderState.error) {
                                  leadingIcon = Icon(
                                    Icons.error_outline_rounded,
                                    size: 20,
                                    color: Colors.redAccent.withValues(alpha: 0.8),
                                  );
                                  subtitleText = status.error != null &&
                                          status.error!.isNotEmpty
                                      ? 'Error'
                                      : 'Failed to load';
                                  subtitleColor =
                                      Colors.redAccent.withValues(alpha: 0.8);
                                } else if (data != null && data.hasLyrics) {
                                  if (data.hasWordSync) {
                                    leadingIcon = const Icon(
                                      Icons.bolt_rounded,
                                      size: 22,
                                      color: Color(0xFF10B981),
                                    );
                                    subtitleText =
                                        'Word-synced • ${data.lines!.length} lines';
                                    subtitleColor = const Color(0xFF10B981);
                                    trailingBadge = Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'WORD-SYNC',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    );
                                  } else if (data.hasSyncedLyrics) {
                                    leadingIcon = Icon(
                                      Icons.sync_rounded,
                                      size: 20,
                                      color: accentColor,
                                    );
                                    subtitleText =
                                        'Line-synced • ${data.lines!.length} lines';
                                    subtitleColor = secondaryColor;
                                    trailingBadge = Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'SYNCED',
                                        style: TextStyle(
                                          color: accentColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    );
                                  } else {
                                    leadingIcon = Icon(
                                      Icons.notes_rounded,
                                      size: 20,
                                      color: secondaryColor,
                                    );
                                    final lineCount =
                                        data.lyrics?.split('\n').length ?? 0;
                                    subtitleText = 'Plain text • $lineCount lines';
                                    subtitleColor = secondaryColor;
                                  }
                                } else {
                                  leadingIcon = Icon(
                                    Icons.remove_circle_outline,
                                    size: 20,
                                    color: secondaryColor.withValues(alpha: 0.4),
                                  );
                                  subtitleText = 'No lyrics found';
                                  subtitleColor =
                                      secondaryColor.withValues(alpha: 0.5);
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: BouncyTouch(
                                    style: BouncyStyle.card,
                                    customScale: 0.98,
                                    onTap: () {
                                      sheetRef
                                          .read(lyricsProvider.notifier)
                                          .selectProvider(provider);
                                      Navigator.pop(sheetContext);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isCurrent 
                                            ? accentColor.withValues(alpha: 0.1)
                                            : textColor.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(14),
                                        border: isCurrent
                                            ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 1)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: isCurrent
                                                  ? accentColor.withValues(alpha: 0.15)
                                                  : (isDark
                                                      ? Colors.white10
                                                      : Colors.black.withValues(alpha: 0.04)),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Center(child: leadingIcon),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  provider.displayName,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: isCurrent
                                                        ? FontWeight.w700
                                                        : FontWeight.w600,
                                                    color: isCurrent ? accentColor : textColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  subtitleText,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: subtitleColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (trailingBadge != null && !isCurrent)
                                            trailingBadge,
                                          if (isCurrent) ...[
                                            if (trailingBadge != null) ...[
                                              trailingBadge,
                                              const SizedBox(width: 8),
                                            ],
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 22,
                                              color: accentColor,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
