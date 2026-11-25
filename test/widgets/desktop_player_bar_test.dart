import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/core/providers/theme_provider.dart';
import 'package:inzx/main.dart' show rootNavigatorKey;
import 'package:inzx/l10n/generated/app_localizations.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/providers/providers.dart';
import 'package:inzx/screens/inzx_connect_screen.dart';
import 'package:inzx/screens/widgets/animated_album_art_view.dart';
import 'package:inzx/screens/widgets/desktop_player_bar.dart';
import 'package:inzx/screens/widgets/desktop_shell.dart' show desktopMiniMode;
import 'package:inzx/screens/widgets/lyrics_view.dart';
import 'package:inzx/screens/widgets/now_playing_screen.dart';
import 'package:inzx/screens/widgets/track_artwork_view.dart';
import 'package:inzx/services/audio_player_service.dart';
import 'package:inzx/services/playback/playback_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Fake implements AudioPlayerService {
  final _volume = ValueNotifier<double>(0.5);

  @override
  double get masterVolume => _volume.value;

  @override
  ValueListenable<double> get masterVolumeListenable => _volume;
}

void main() {
  testWidgets('the mini player uses the canvas and releases it in lyrics mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AnimatedAlbumArtNotifier.animatedArtPrefKey: false,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    desktopMiniLyrics.value = false;
    addTearDown(() => desktopMiniLyrics.value = false);

    final playback = StreamController<PlaybackState>();
    addTearDown(playback.close);
    const track = Track(
      id: 'mini-first',
      title: 'First song',
      artist: 'Artist',
      duration: Duration(minutes: 4),
    );
    final next = track.copyWith(id: 'mini-next', title: 'Next song');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(_Player()),
          playbackStateProvider.overrideWith((_) => playback.stream),
          isLiveProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 340,
              child: DesktopPopoutPlayer(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byType(AnimatedAlbumArtView);
    playback.add(const PlaybackState(currentTrack: track));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedAlbumArtView>(canvas).track, track);
    expect(
      find.descendant(of: canvas, matching: find.byType(TrackArtworkView)),
      findsOneWidget,
    );

    playback.add(PlaybackState(currentTrack: next));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedAlbumArtView>(canvas).track, next);

    desktopMiniLyrics.value = true;
    await tester.pumpAndSettle();
    expect(canvas, findsNothing);
    expect(find.text('Lyrics aren’t available for live streams'), findsOneWidget);
  });

  testWidgets('compact player shows artwork and hover lyrics/expand controls', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 340);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    desktopMiniLyrics.value = false;
    const track = Track(id: 'mini-test', title: 'Mini song', artist: 'Artist', duration: Duration(minutes: 3));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(_Player()),
        playbackStateProvider.overrideWith((_) => Stream.value(const PlaybackState(currentTrack: track))),
        playerAlbumColorsProvider.overrideWith((_) => AlbumColorsNotifier()),
      ],
      child: const MaterialApp(home: Scaffold(body: DesktopPopoutPlayer())),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesktopPopoutPlayer)), const Size(320, 340));
    expect(find.byType(DesktopPlayerBar), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(160, 170));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show lyrics'), findsOneWidget);
    expect(find.byTooltip('Back to full window'), findsOneWidget);
    expect(find.text('Mini song'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

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
    const state = PlaybackState(currentTrack: track, queue: [track]);
    addTearDown(() => desktopMiniMode.value = false);

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    NowPlayingScreen.showDesktop();
    await tester.pumpAndSettle();
    final nowPlaying = find.byType(NowPlayingScreen);
    expect(nowPlaying, findsOneWidget);

    final lyrics = find.byType(LyricsView, skipOffstage: false);
    final queue = find.byType(ReorderableListView, skipOffstage: false);
    expect(lyrics, findsNothing);
    expect(queue, findsOneWidget);
    await tester.tap(find.text('LYRICS'));
    await tester.pumpAndSettle();
    expect(lyrics, findsOneWidget);
    expect(queue, findsNothing);

    desktopMiniMode.value = true;
    await tester.pumpAndSettle();
    expect(nowPlaying, findsOneWidget);
    expect(lyrics, findsNothing);
    desktopMiniMode.value = false;
    await tester.pumpAndSettle();
    expect(lyrics, findsOneWidget);

    await tester.tap(connect);
    await tester.pumpAndSettle();
    final pane = find.descendant(
      of: nowPlaying,
      matching: find.byType(InzxConnectPanel),
    );
    expect(pane, findsOneWidget);
    expect(tester.getTopLeft(pane).dx, greaterThan(720 / 2));
    expect(find.text('CONNECT'), findsNothing);
    expect(find.byType(InzxConnectScreen), findsNothing);
    expect(lyrics, findsNothing);

    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
    expect(nowPlaying, findsOneWidget);
    expect(lyrics, findsOneWidget);
    await tester.tap(find.text('UP NEXT'));
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing);
    expect(queue, findsOneWidget);
    NowPlayingScreen.closeDesktop();
    await tester.pumpAndSettle();

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
