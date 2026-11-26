import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/core/utils/platform_utils.dart';
import 'package:inzx/l10n/generated/app_localizations.dart';
import 'package:inzx/providers/providers.dart';
import 'package:inzx/screens/music_app.dart';
import 'package:inzx/screens/tabs/desktop_explore_tab.dart';
import 'package:inzx/screens/tabs/folders_tab.dart';
import 'package:inzx/screens/tabs/home_tab.dart';
import 'package:inzx/screens/tabs/library_tab.dart';
import 'package:inzx/screens/widgets/desktop_shell.dart';
import 'package:inzx/services/ytmusic_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InnerTube extends Fake implements InnerTubeService {}

class _HomePage extends HomePageNotifier {
  _HomePage() : super(_InnerTube());

  @override
  Future<void> loadInitial() async {}
}

void main() {
  testWidgets('main tabs mount on first visit and keep their state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackStateProvider.overrideWith((_) => const Stream.empty()),
          localCurrentTrackProvider.overrideWith((_) => const Stream.empty()),
          isInJamSessionProvider.overrideWithValue(false),
          albumColorsProvider.overrideWithValue(AlbumColors.defaultColors()),
          effectiveAccentColorProvider.overrideWithValue(Colors.blue),
          appAccountProvider.overrideWithValue(null),
          jioSaavnEnabledProvider.overrideWithValue(false),
          ytMusicHomePageStateProvider.overrideWith((_) => _HomePage()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MusicApp(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final home = find.byType(MusicHomeTab, skipOffstage: false);
    final library = find.byType(MusicLibraryTab, skipOffstage: false);
    expect(home, findsOneWidget);
    expect(library, findsNothing);
    expect(find.byType(DesktopExploreTab, skipOffstage: false), findsNothing);
    expect(find.byType(MusicFoldersTab, skipOffstage: false), findsNothing);

    final container = ProviderScope.containerOf(tester.element(home));
    final selectedTab = container.read(desktopTabProvider.notifier);
    selectedTab.state = 2;
    await tester.pump();
    final libraryState = tester.state(library);
    expect(TickerMode.valuesOf(tester.element(library)).enabled, isTrue);
    expect(TickerMode.valuesOf(tester.element(home)).enabled, isFalse);

    selectedTab.state = 0;
    await tester.pump();
    expect(tester.state(library), same(libraryState));
    expect(TickerMode.valuesOf(tester.element(library)).enabled, isFalse);
  }, skip: !isDesktop);
}
