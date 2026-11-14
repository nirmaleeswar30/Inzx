import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/services/audio_player_service.dart';
import 'package:inzx/services/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(WidgetSyncService.resetForTest);

  test('the home widget can switch between PC and phone playback', () async {
    const channel = MethodChannel('inzx/widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payloads = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'syncPlaybackState') {
        payloads.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const state = PlaybackState(
      currentTrack: Track(
        id: 'connect-test',
        title: 'Track',
        artist: 'Artist',
        duration: Duration(minutes: 2),
      ),
      isPlaying: true,
    );

    await WidgetSyncService.syncPlaybackState(state, outputDevice: 'Studio PC');
    await WidgetSyncService.syncPlaybackState(state);

    expect(payloads, hasLength(2));
    expect(payloads.first['remoteOutput'], true);
    expect(payloads.first['artist'], 'Artist · Studio PC');
    expect(payloads.first['isPlaying'], true);
    expect(payloads.last['remoteOutput'], isNull);
    expect(payloads.last['artist'], 'Artist');
  });

  test('late artwork keeps the current track ID and remote routing', () async {
    const channel = MethodChannel('inzx/widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payloads = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      payloads.add(call.arguments as Map<Object?, Object?>);
      return true;
    });
    final download = WidgetSyncService.download;
    final readCache = WidgetSyncService.readCache;
    final artGrace = WidgetSyncService.artGrace;
    final cover = Completer<Uint8List?>();
    WidgetSyncService.artGrace = Duration.zero;
    WidgetSyncService.readCache = (_) async => null;
    WidgetSyncService.download = (_, _) => cover.future;
    addTearDown(() {
      WidgetSyncService.download = download;
      WidgetSyncService.readCache = readCache;
      WidgetSyncService.artGrace = artGrace;
      messenger.setMockMethodCallHandler(channel, null);
    });
    const state = PlaybackState(
      currentTrack: Track(
        id: 'playing-on-pc',
        title: 'Track',
        artist: 'Artist',
        duration: Duration(minutes: 2),
        thumbnailUrl: 'https://example.com/cover.jpg',
      ),
      isPlaying: true,
    );

    await WidgetSyncService.syncPlaybackState(state, outputDevice: 'Studio PC');
    cover.complete(Uint8List.fromList([1, 2, 3]));
    await pumpEventQueue();

    expect(payloads, hasLength(2));
    expect(payloads.first['remoteOutput'], isTrue);
    expect(payloads.last['trackId'], payloads.first['trackId']);
    expect(payloads.last['artworkOnly'], isTrue);
    expect(payloads.last['artBytes'], [1, 2, 3]);
  });
}
