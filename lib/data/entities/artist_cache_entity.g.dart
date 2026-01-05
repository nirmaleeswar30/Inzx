// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artist_cache_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ArtistCacheEntityAdapter extends TypeAdapter<ArtistCacheEntity> {
  @override
  final int typeId = 8;

  @override
  ArtistCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArtistCacheEntity(
      artistId: fields[0] as String,
      artistJson: fields[1] as String,
      cachedAt: fields[2] as DateTime,
      ttlMinutes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ArtistCacheEntity obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.artistId)
      ..writeByte(1)
      ..write(obj.artistJson)
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
      other is ArtistCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
