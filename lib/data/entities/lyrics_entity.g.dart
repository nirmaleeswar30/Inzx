// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LyricsEntityAdapter extends TypeAdapter<LyricsEntity> {
  @override
  final int typeId = 5;

  @override
  LyricsEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LyricsEntity(
      trackId: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      syncedLyrics: fields[3] as String?,
      plainLyrics: fields[4] as String?,
      provider: fields[5] as String,
      cachedAt: fields[6] as DateTime,
      ttlDays: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, LyricsEntity obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.trackId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.syncedLyrics)
      ..writeByte(4)
      ..write(obj.plainLyrics)
      ..writeByte(5)
      ..write(obj.provider)
      ..writeByte(6)
      ..write(obj.cachedAt)
      ..writeByte(7)
      ..write(obj.ttlDays);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
