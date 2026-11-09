/// Formats a playback time as `mm:ss`, or `h:mm:ss` from one hour up.
String formatPlaybackDuration(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');

  final minutes = twoDigits(d.inMinutes.remainder(60));
  final seconds = twoDigits(d.inSeconds.remainder(60));
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
