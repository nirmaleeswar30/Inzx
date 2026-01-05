import 'package:hive/hive.dart';

part 'playback_entity.g.dart';

@HiveType(typeId: 2)
class PlaybackEntity extends HiveObject {
  @HiveField(0)
  late List<String> queueIds; // Track IDs in queue order

  @HiveField(1)
  late int currentTrackIndex;

  @HiveField(2)
  late int positionMillis;

  @HiveField(3)
  late bool isPlaying;

  @HiveField(4)
  late int loopMode; // 0: off, 1: all, 2: one

  @HiveField(5)
  late bool isShuffle;

  @HiveField(6)
  late double playbackSpeed;

  @HiveField(7)
  late DateTime savedAt;

  PlaybackEntity({
    required this.queueIds,
    required this.currentTrackIndex,
    required this.positionMillis,
    required this.isPlaying,
    required this.loopMode,
    required this.isShuffle,
    required this.playbackSpeed,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  bool isQueueEmpty() => queueIds.isEmpty;

  bool isAtEnd() => currentTrackIndex >= queueIds.length - 1;

  String? getCurrentTrackId() =>
      currentTrackIndex >= 0 && currentTrackIndex < queueIds.length
      ? queueIds[currentTrackIndex]
      : null;
}
