import 'playback/playback_data.dart';

/// Where a download's audio can come from.
enum DownloadSourceKind { addonLossless, jioSaavn, youtube }

/// The sources to try for a download, best first. The same ladder streaming
/// climbs: Low and Medium are YouTube only, High is the best lossy copy, and
/// Max adds lossless. YouTube is last on every rung, so a track neither of
/// the others has still downloads.
List<DownloadSourceKind> downloadSourceOrder(
  AudioQuality quality, {
  required bool losslessAvailable,
  required bool jioSaavnEnabled,
}) {
  final wantsLossless = quality == AudioQuality.max;
  final wantsJioSaavn =
      quality == AudioQuality.high || quality == AudioQuality.max;
  return [
    if (wantsLossless && losslessAvailable) DownloadSourceKind.addonLossless,
    if (wantsJioSaavn && jioSaavnEnabled) DownloadSourceKind.jioSaavn,
    DownloadSourceKind.youtube,
  ];
}
