import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/l10n/generated/app_localizations.dart';
import 'package:inzx/main.dart' show rootNavigatorKey;
import 'package:inzx/providers/providers.dart';
import 'package:inzx/screens/search_screen.dart';
import 'package:inzx/screens/widgets/desktop_shell.dart';
import 'package:inzx/services/audio_player_service.dart';
import 'package:inzx/services/search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlaybackSpy extends Fake implements AudioPlayerService {
  int toggles = 0;

  @override
  Future<void> togglePlayPause() async => toggles++;
}

void main() {
  testWidgets('desktop sidebar animates and search keeps a single focused field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final playback = _PlaybackSpy();
    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(playback),
        playbackStateProvider.overrideWith((ref) => const Stream.empty()),
        albumColorsProvider.overrideWithValue(AlbumColors.defaultColors()),
        effectiveAccentColorProvider.overrideWithValue(Colors.blue),
        currentJamSessionProvider.overrideWith((ref) => Stream.value(null)),
        desktopLibraryProvider.overrideWithValue(const [
          DesktopLibraryEntry(
            type: DesktopLibraryType.playlist,
            id: 'fixture',
            title: 'Example playlist',
          ),
        ]),
        appAccountProvider.overrideWithValue(null),
        enhancedSearchProvider.overrideWith(
          (ref) async =>
              EnhancedSearchResults.empty(ref.watch(searchQueryProvider)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) =>
              DesktopShortcuts(child: DesktopAppFrame(child: child!)),
          home: const Scaffold(body: Text('Home page')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entryY = tester.getCenter(find.text('Example playlist')).dy;
    final sidebar = container.read(desktopSidebarCollapsedProvider.notifier);
    sidebar.state = true;
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(36, entryY));
    await tester.pump();
    sidebar.state = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Example playlist'), findsOneWidget);
    await mouse.removePointer();

    final field = find.byType(TextField);
    await tester.tap(field, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.enterText(field, 'Maya');
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(playback.toggles, 0);
    // The Windows text input plugin supplies the character after the key event.
    await tester.enterText(field, 'Maya Nadhi');
    await tester.pumpAndSettle();
    expect(container.read(searchQueryProvider), 'Maya Nadhi');

    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(playback.toggles, 1);
  });
}
