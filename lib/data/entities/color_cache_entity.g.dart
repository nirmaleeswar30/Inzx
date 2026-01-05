// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'color_cache_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ColorCacheEntityAdapter extends TypeAdapter<ColorCacheEntity> {
  @override
  final int typeId = 10;

  @override
  ColorCacheEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ColorCacheEntity(
      imageUrl: fields[0] as String,
      accent: fields[1] as int,
      accentLight: fields[2] as int,
      accentDark: fields[3] as int,
      backgroundPrimary: fields[4] as int,
      backgroundSecondary: fields[5] as int,
      surface: fields[6] as int,
      onBackground: fields[7] as int,
      onSurface: fields[8] as int,
      cachedAt: fields[9] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ColorCacheEntity obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.imageUrl)
      ..writeByte(1)
      ..write(obj.accent)
      ..writeByte(2)
      ..write(obj.accentLight)
      ..writeByte(3)
      ..write(obj.accentDark)
      ..writeByte(4)
      ..write(obj.backgroundPrimary)
      ..writeByte(5)
      ..write(obj.backgroundSecondary)
      ..writeByte(6)
      ..write(obj.surface)
      ..writeByte(7)
      ..write(obj.onBackground)
      ..writeByte(8)
      ..write(obj.onSurface)
      ..writeByte(9)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorCacheEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
