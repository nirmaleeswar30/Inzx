import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/providers/providers.dart';
import 'package:inzx/screens/inzx_connect_screen.dart';
import 'package:inzx/screens/onboarding_screen.dart';
import 'package:inzx/screens/playlist_transfer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed in or out from the start, with no auth service behind it.
class _Auth extends YTMusicAuthNotifier {
  _Auth({required this.signedIn});

  final bool signedIn;

  @override
  YTMusicAuthState build() =>
      YTMusicAuthState(isLoggedIn: signedIn, isLoading: false);
}

class _SavedPlaylists extends YtMusicSavedPlaylistsNotifier {
  _SavedPlaylists(this.onLoad);

  final VoidCallback onLoad;

  @override
  List<Playlist> build() {
    onLoad();
    return [];
  }
}

void main() {
  testWidgets('the transfer screen opens the two YouTube Music partner links', (
    tester,
  ) async {
    final launches = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      launches.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    var refreshes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ytMusicAuthStateProvider.overrideWith(() => _Auth(signedIn: true)),
          ytMusicSavedPlaylistsProvider.overrideWith(
            () => _SavedPlaylists(() => refreshes++),
          ),
        ],
        child: const MaterialApp(home: PlaylistTransferScreen()),
      ),
    );

    await tester.tap(find.text('TuneMyMusic'));
    await tester.tap(find.text('Soundiiz'));
    await tester.pump();
    expect(launches.map((call) => call.arguments['url']), [
      'https://www.tunemymusic.com/transfer?mode=youtubemusic',
      'https://soundiiz.com/partner/youtube-music',
    ]);
    expect(
      launches.every((call) => call.arguments['useWebView'] == false),
      isTrue,
    );

    await tester.tap(find.text('Refresh playlists'));
    await tester.pump();
    expect(refreshes, 1);
  });

  testWidgets('onboarding opens the lossless guide before Inzx Connect', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    final launches = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      launches.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var finished = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ytMusicAuthStateProvider.overrideWith(() => _Auth(signedIn: false)),
        ],
        child: MaterialApp(
          home: OnboardingScreen(onFinished: () => finished = true),
        ),
      ),
    );

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue without signing in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(PlaylistTransferScreen.title), findsOneWidget);
    expect(find.text('Other apps'), findsOneWidget);
    final signIn = find.text('Sign in to Inzx to see your playlists');
    final next = find.text('Continue');
    expect(signIn, findsOneWidget);
    expect(
      tester.getTopLeft(next).dy - tester.getBottomLeft(signIn).dy,
      lessThan(90),
    );
    expect(finished, isFalse);

    await tester.tap(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Lossless add-ons'), findsOneWidget);
    await tester.tap(find.text('Read the lossless guide'));
    await tester.pump();
    expect(
      launches.single.arguments['url'],
      'https://inzx.nirmaleeswar.dev/docs/audio#lossless-addons',
    );
    expect(launches.single.arguments['useWebView'], isFalse);

    await tester.tap(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(InzxConnectScreen.title), findsOneWidget);
    expect(find.textContaining('Windows and Linux'), findsOneWidget);
    expect(find.textContaining('Settings → Inzx Connect'), findsOneWidget);
    expect(finished, isFalse);

    final finish = find.text('Finish setup');
    await tester.tap(finish);
    await tester.pump();
    expect(finished, isTrue);
  });
}
