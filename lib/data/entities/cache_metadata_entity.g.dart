// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_metadata_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CacheMetadataEntityAdapter extends TypeAdapter<CacheMetadataEntity> {
  @override
  final int typeId = 3;

  @override
  CacheMetadataEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CacheMetadataEntity(
      key: fields[0] as String,
      ttlMinutes: fields[2] as int,
      sourceId: fields[3] as String?,
      cachedAt: fields[1] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CacheMetadataEntity obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.cachedAt)
      ..writeByte(2)
      ..write(obj.ttlMinutes)
      ..writeByte(3)
      ..write(obj.sourceId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheMetadataEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
