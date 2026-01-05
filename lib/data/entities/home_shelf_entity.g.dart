// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_shelf_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HomePageCacheEntityAdapter extends TypeAdapter<HomePageCacheEntity> {
  @override
  final int typeId = 6;

  @override
  HomePageCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HomePageCacheEntity(
      shelvesJson: fields[0] as String,
      continuationToken: fields[1] as String?,
      cachedAt: fields[2] as DateTime,
      ttlMinutes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HomePageCacheEntity obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.shelvesJson)
      ..writeByte(1)
      ..write(obj.continuationToken)
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
      other is HomePageCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
