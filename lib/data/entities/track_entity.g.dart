// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrackEntityAdapter extends TypeAdapter<TrackEntity> {
  @override
  final int typeId = 1;

  @override
  TrackEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrackEntity(
      id: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      album: fields[3] as String?,
      duration: fields[4] as int,
      thumbnailUrl: fields[5] as String?,
      isExplicit: fields[6] as bool,
      isLiked: fields[7] as bool,
      addedAt: fields[8] as DateTime?,
      localFilePath: fields[9] as String?,
      cachedAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, TrackEntity obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.duration)
      ..writeByte(5)
      ..write(obj.thumbnailUrl)
      ..writeByte(6)
      ..write(obj.isExplicit)
      ..writeByte(7)
      ..write(obj.isLiked)
      ..writeByte(8)
      ..write(obj.addedAt)
      ..writeByte(9)
      ..write(obj.localFilePath)
      ..writeByte(10)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
