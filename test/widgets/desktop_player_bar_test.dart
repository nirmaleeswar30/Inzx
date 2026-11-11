import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/main.dart' show rootNavigatorKey;
import 'package:inzx/models/models.dart';
import 'package:inzx/providers/providers.dart';
import 'package:inzx/screens/inzx_connect_screen.dart';
import 'package:inzx/screens/widgets/desktop_player_bar.dart';
import 'package:inzx/services/audio_player_service.dart';
import 'package:inzx/services/playback/playback_data.dart';

class _Player extends Fake implements AudioPlayerService {
  @override
  double get masterVolume => 0.5;
}

void main() {
  testWidgets('the desktop bar fits Connect and follows playback quality', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(720, 540);

    final playback = StreamController<PlaybackState>();
    final upgrading = StreamController<bool>();
    final downgrading = StreamController<bool>();
    addTearDown(playback.close);
    addTearDown(upgrading.close);
    addTearDown(downgrading.close);
    const track = Track(
      id: 'test',
      title: 'Song title',
      artist: 'Artist name',
      duration: Duration(minutes: 4),
    );
    const state = PlaybackState(currentTrack: track);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(_Player()),
          playbackStateProvider.overrideWith((_) => playback.stream),
          positionStreamProvider.overrideWith((_) => const Stream.empty()),
          losslessUpgradingProvider.overrideWith((_) => upgrading.stream),
          qualityDowngradingProvider.overrideWith((_) => downgrading.stream),
          albumColorsProvider.overrideWithValue(AlbumColors.defaultColors()),
          effectiveAccentColorProvider.overrideWithValue(Colors.red),
          isTrackLikedProvider.overrideWith((_, _) => false),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Material(
                  child: Column(
                    children: [
                      Expanded(child: child!),
                      const DesktopPlayerBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          home: const SizedBox.shrink(),
        ),
      ),
    );
    playback.add(state);
    await tester.pumpAndSettle();

    final connect = find.byTooltip(InzxConnectScreen.title);
    expect(tester.getCenter(connect).dx, greaterThan(720 / 2));
    expect(find.text('Lossless'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.byType(InzxConnectScreen), findsOneWidget);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(InzxConnectScreen), findsNothing);

    upgrading.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Upgrading'), findsOneWidget);

    playback.add(
      state.copyWith(
        currentPlaybackData: PlaybackData(
          format: const AudioFormat(
            mimeType: 'audio/flac',
            bitrate: 1000000,
            sampleRate: 96000,
            bitsPerSample: 24,
          ),
          streamUrl: '',
          streamExpiresInSeconds: 0,
          fetchedAt: DateTime.utc(2026),
        ),
      ),
    );
    upgrading.add(false);
    await tester.pumpAndSettle();
    final badge = find.text('Hi-Res Lossless');
    expect(
      tester.getTopLeft(badge).dy,
      greaterThan(tester.getTopLeft(find.text(track.artist)).dy),
    );
    expect(find.text('Upgrading'), findsNothing);

    for (final width in [979.0, 980.0, 1100.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 540);
      await tester.pumpAndSettle();
      expect(connect, findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    downgrading.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Downgrading'), findsOneWidget);
    playback.add(state);
    downgrading.add(false);
    await tester.pumpAndSettle();
    expect(find.text('Downgrading'), findsNothing);
    expect(badge, findsNothing);
  });
}
