// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadEntityAdapter extends TypeAdapter<DownloadEntity> {
  @override
  final int typeId = 4;

  @override
  DownloadEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadEntity(
      trackId: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      album: fields[3] as String?,
      durationMs: fields[4] as int,
      thumbnailUrl: fields[5] as String?,
      localPath: fields[6] as String,
      totalBytes: fields[7] as int,
      downloadedAt: fields[8] as DateTime?,
      quality: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadEntity obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.trackId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.durationMs)
      ..writeByte(5)
      ..write(obj.thumbnailUrl)
      ..writeByte(6)
      ..write(obj.localPath)
      ..writeByte(7)
      ..write(obj.totalBytes)
      ..writeByte(8)
      ..write(obj.downloadedAt)
      ..writeByte(9)
      ..write(obj.quality);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
