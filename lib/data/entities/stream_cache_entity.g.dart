// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_cache_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StreamCacheEntityAdapter extends TypeAdapter<StreamCacheEntity> {
  @override
  final int typeId = 11;

  @override
  StreamCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StreamCacheEntity(
      videoId: fields[0] as String,
      streamUrl: fields[1] as String,
      expiresInSeconds: fields[2] as int,
      fetchedAt: fields[3] as DateTime,
      mimeType: fields[4] as String,
      bitrate: fields[5] as int,
      contentLength: fields[6] as int?,
      codec: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, StreamCacheEntity obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.videoId)
      ..writeByte(1)
      ..write(obj.streamUrl)
      ..writeByte(2)
      ..write(obj.expiresInSeconds)
      ..writeByte(3)
      ..write(obj.fetchedAt)
      ..writeByte(4)
      ..write(obj.mimeType)
      ..writeByte(5)
      ..write(obj.bitrate)
      ..writeByte(6)
      ..write(obj.contentLength)
      ..writeByte(7)
      ..write(obj.codec);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
