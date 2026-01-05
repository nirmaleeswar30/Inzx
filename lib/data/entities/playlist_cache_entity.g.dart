// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_cache_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlaylistCacheEntityAdapter extends TypeAdapter<PlaylistCacheEntity> {
  @override
  final int typeId = 9;

  @override
  PlaylistCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaylistCacheEntity(
      playlistId: fields[0] as String,
      playlistJson: fields[1] as String,
      cachedAt: fields[2] as DateTime,
      ttlMinutes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistCacheEntity obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.playlistId)
      ..writeByte(1)
      ..write(obj.playlistJson)
      ..writeByte(2)
      ..write(obj.cachedAt)
      ..writeByte(3)
      ..write(obj.ttlMinutes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
