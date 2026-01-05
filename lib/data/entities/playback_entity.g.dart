// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlaybackEntityAdapter extends TypeAdapter<PlaybackEntity> {
  @override
  final int typeId = 2;

  @override
  PlaybackEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaybackEntity(
      queueIds: (fields[0] as List).cast<String>(),
      currentTrackIndex: fields[1] as int,
      positionMillis: fields[2] as int,
      isPlaying: fields[3] as bool,
      loopMode: fields[4] as int,
      isShuffle: fields[5] as bool,
      playbackSpeed: fields[6] as double,
      savedAt: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackEntity obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.queueIds)
      ..writeByte(1)
      ..write(obj.currentTrackIndex)
      ..writeByte(2)
      ..write(obj.positionMillis)
      ..writeByte(3)
      ..write(obj.isPlaying)
      ..writeByte(4)
      ..write(obj.loopMode)
      ..writeByte(5)
      ..write(obj.isShuffle)
      ..writeByte(6)
      ..write(obj.playbackSpeed)
      ..writeByte(7)
      ..write(obj.savedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
