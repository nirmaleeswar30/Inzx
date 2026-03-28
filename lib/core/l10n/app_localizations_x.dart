import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import '../../l10n/generated/app_localizations.dart';

String localizeDownloadError(AppLocalizations l10n, String? error) {
  final normalizedError = (error ?? '').trim();
  if (normalizedError.isEmpty) {
    return l10n.unknownError;
  }

  final withoutException = normalizedError.replaceFirst(
    RegExp(r'^Exception:\s*'),
    '',
  );

  if (withoutException.contains('File was not created')) {
    return l10n.downloadFileNotCreated;
  }

  return l10n.failedWithError(withoutException);
}

String formatStorageAmount(AppLocalizations l10n, num bytes) {
  final megabytes = bytes / (1024 * 1024);
  if (megabytes >= 1024) {
    return l10n.gigabytesValue((megabytes / 1024).toStringAsFixed(1));
  }
  return l10n.megabytesValue(megabytes.toStringAsFixed(1));
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String metadataLine(Iterable<String?> parts) {
    final visibleParts = parts
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    return visibleParts.join(' • ');
  }

  String trackSubtitle(String artist, String? formattedDuration) {
    final duration = formattedDuration?.trim();
    final visibleDuration =
        duration == null || duration.isEmpty || duration == '0:00'
        ? null
        : duration;
    return metadataLine([artist, visibleDuration]);
  }

  String albumSubtitle(String artist, Object? year) {
    return metadataLine([artist, year?.toString()]);
  }

  String playlistSubtitle(String author, int? trackCount) {
    return metadataLine([
      author,
      trackCount == null ? null : l10n.songsCount(trackCount),
    ]);
  }

  String artistSubtitle(String? formattedSubscribers) {
    return metadataLine([l10n.artistLabel, formattedSubscribers]);
  }

  String compactNumber(num value) {
    return NumberFormat.compact(locale: l10n.localeName).format(value);
  }
}
