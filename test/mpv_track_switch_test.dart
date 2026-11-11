import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = File(
    'build/windows/x64/_deps/inzx_libmpv-src/libmpv-2.dll',
  ).absolute;

  test('switching to a broken DASH track leaves the player usable', () async {
    JustAudioMediaKit.ensureInitialized(libmpv: library.path);
    final dir = await Directory.systemTemp.createTemp('inzx-track-switch');
    addTearDown(() => dir.delete(recursive: true));
    final first = File('${dir.path}/first.wav')..writeAsBytesSync(_silentWav());
    final next = File('${dir.path}/next.wav')..writeAsBytesSync(_silentWav());
    final player = AudioPlayer();
    addTearDown(player.dispose);
    await player.setVolume(0);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var failedFragments = 0;
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/broken.mpd') {
        response.headers.contentType = ContentType('application', 'dash+xml');
        response.write(_brokenManifest);
      } else {
        failedFragments++;
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });

    Future<void> playAndWaitForPosition(File file) async {
      await player.setAudioSource(AudioSource.uri(file.uri));
      unawaited(player.play());
      await player.positionStream
          .firstWhere((position) => position > const Duration(milliseconds: 40))
          .timeout(const Duration(seconds: 8));
      expect(player.processingState, ProcessingState.ready);
    }

    await playAndWaitForPosition(first);
    final broken = Uri.http('127.0.0.1:${server.port}', 'broken.mpd');
    await expectLater(
      player
          .setAudioSource(DashAudioSource(broken))
          .timeout(const Duration(seconds: 8)),
      throwsA(isA<PlayerException>()),
    );
    expect(failedFragments, greaterThan(0));
    await playAndWaitForPosition(next);
  }, skip: !Platform.isWindows || !library.existsSync());
}

// A static MPD with a deliberately missing initialization fragment.
const _brokenManifest = r'''<?xml version="1.0" encoding="utf-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
  profiles="urn:mpeg:dash:profile:isoff-live:2011"
  type="static" mediaPresentationDuration="PT3S" minBufferTime="PT1S">
  <Period id="0" start="PT0S">
    <AdaptationSet id="0" contentType="audio">
      <Representation id="0" mimeType="audio/mp4" codecs="flac" bandwidth="128000">
        <SegmentTemplate timescale="48000" initialization="missing-init.m4s"
          media="chunk-$Number$.m4s" startNumber="1">
          <SegmentTimeline><S t="0" d="48000" r="2"/></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';

Uint8List _silentWav() {
  const sampleRate = 48000;
  const dataSize = sampleRate * 2 * 3;
  final data = ByteData(44 + dataSize)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + dataSize, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666D7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, dataSize, Endian.little);
  return data.buffer.asUint8List();
}
