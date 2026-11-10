import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/canvas/mpv_canvas_player.dart';

/// Runs where a built libmpv is around (a Windows build of this repo, or a
/// system libmpv on Linux). The audio-only Windows libmpv has no video
/// decoders but does decode PNG, so a generated image stands in for the
/// canvas: it exercises the render API, the frame hand-off between
/// isolates, the byte order and the alpha fix.
void main() {
  final dll = '${Directory.current.path}/build/windows/x64/libmpv/libmpv-2.dll';
  final library = Platform.isWindows ? dll : null;
  final skip = Platform.isWindows && !File(dll).existsSync();

  testWidgets('renders frames through the software render API', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('mpv_canvas_test');
      final png = File('${dir.path}/half_red_half_blue.png')..writeAsBytesSync(_png(200, 120));
      final player = MpvCanvasPlayer(
        library: library,
        maxSide: 100, // scaled down: 100x60
        options: const {'image-display-duration': 'inf'},
      );
      final ok = await player.open(png.path);
      final image = player.frame.value;
      expect(ok, isTrue);
      expect(image, isNotNull);
      expect(image!.width, 100);
      expect(image.height, 60);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      List<int> at(int x, int y) => bytes.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);
      expect(at(20, 30), [255, 0, 0, 255]); // red half, opaque
      expect(at(80, 30), [0, 0, 255, 255]); // blue half, opaque
      player.dispose();
      await dir.delete(recursive: true);
    });
  }, skip: skip);
}

/// A PNG whose left half is red and right half blue.
Uint8List _png(int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w; x++) {
      raw.add(x < w ~/ 2 ? const [255, 0, 0] : const [0, 0, 255]);
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final t = type.codeUnits;
    final b = BytesBuilder()
      ..add(_u32(data.length))
      ..add(t)
      ..add(data)
      ..add(_u32(_crc32([...t, ...data])));
    return b.toBytes();
  }

  final ihdr = [..._u32(w), ..._u32(h), 8, 2, 0, 0, 0];
  return (BytesBuilder()
        ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(chunk('IHDR', ihdr))
        ..add(chunk('IDAT', ZLibCodec().encode(raw.toBytes())))
        ..add(chunk('IEND', const [])))
      .toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
