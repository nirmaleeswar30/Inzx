// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_cache_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AlbumCacheEntityAdapter extends TypeAdapter<AlbumCacheEntity> {
  @override
  final int typeId = 7;

  @override
  AlbumCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AlbumCacheEntity(
      albumId: fields[0] as String,
      albumJson: fields[1] as String,
      cachedAt: fields[2] as DateTime,
      ttlMinutes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, AlbumCacheEntity obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.albumId)
      ..writeByte(1)
      ..write(obj.albumJson)
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
      other is AlbumCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
