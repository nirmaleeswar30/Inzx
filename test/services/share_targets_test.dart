import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/screens/widgets/share_sheet.dart';
import 'package:inzx/services/share/share_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('orderShareApps', () {
    const both = {ShareApp.instagram, ShareApp.snapchat};

    test('Instagram leads until something has been used', () {
      expect(orderShareApps(recent: const [], installed: both), [
        ShareApp.instagram,
        ShareApp.snapchat,
      ]);
    });

    test('the most recently used leads after that', () {
      expect(orderShareApps(recent: const ['snapchat'], installed: both), [
        ShareApp.snapchat,
        ShareApp.instagram,
      ]);
      expect(
        orderShareApps(recent: const ['instagram', 'snapchat'], installed: both),
        [ShareApp.instagram, ShareApp.snapchat],
      );
    });

    test('apps that are not installed are left out', () {
      expect(
        orderShareApps(
          recent: const ['instagram'],
          installed: const {ShareApp.snapchat},
        ),
        [ShareApp.snapchat],
      );
      expect(orderShareApps(recent: const [], installed: const {}), isEmpty);
    });

    test('names it no longer knows are ignored', () {
      expect(orderShareApps(recent: const ['tiktok'], installed: both), [
        ShareApp.instagram,
        ShareApp.snapchat,
      ]);
    });
  });

  group('SharePreferences', () {
    test('using an app moves it to the front without repeating it', () async {
      SharedPreferences.setMockInitialValues({});
      const prefs = SharePreferences();
      await prefs.markUsed(ShareApp.instagram);
      await prefs.markUsed(ShareApp.snapchat);
      await prefs.markUsed(ShareApp.instagram);
      expect(await prefs.recentApps(), ['instagram', 'snapchat']);
    });

    test('remembers the card style and theme', () async {
      SharedPreferences.setMockInitialValues({});
      const prefs = SharePreferences();
      await prefs.saveCardLook('liquid', 3);
      expect(await prefs.cardStyle(), 'liquid');
      expect(await prefs.cardTheme(), 3);
    });
  });

  group('NativeShare on a build without the bridge', () {
    // No handler is registered in tests, which is exactly what an OTA patch
    // sees on an older install: the sheet must fall back, not throw.
    const native = NativeShare();

    test('reports no bridge', () async {
      expect(await native.installedApps(), isNull);
    });

    test('sending and saving fail quietly', () async {
      expect(await native.sendTo(ShareApp.instagram, 'x.png'), isFalse);
      expect(await native.saveToGallery('x.png', 'x.png'), isFalse);
    });
  });

  group('NativeShare with the bridge', () {
    const channel = MethodChannel('inzx/share');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads which apps are installed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'installedTargets');
        return ['snapchat'];
      });
      expect(await const NativeShare().installedApps(), {ShareApp.snapchat});
    });

    test('sends the image and link to the named app', () async {
      late Map<Object?, Object?> args;
      messenger.setMockMethodCallHandler(channel, (call) async {
        args = call.arguments as Map<Object?, Object?>;
        return call.method == 'shareImage';
      });
      final sent = await const NativeShare().sendTo(
        ShareApp.instagram,
        '/cache/card.png',
        text: 'https://inzx.nirmaleeswar.dev/s/abc',
      );
      expect(sent, isTrue);
      expect(args['target'], 'instagram');
      expect(args['path'], '/cache/card.png');
      expect(args['text'], 'https://inzx.nirmaleeswar.dev/s/abc');
    });
  });

  group('lyricEntriesFrom', () {
    test('strips tags and keeps each line\'s start time', () {
      expect(
        lyricEntriesFrom(
          '[00:01.00]First <00:01.20>line\n\n[00:03.00]\n[01:04.50]Second line\n',
        ),
        [
          (text: 'First line', timeMs: 1000),
          (text: 'Second line', timeMs: 64500),
        ],
      );
    });

    test('plain lyrics have no timing', () {
      expect(lyricEntriesFrom('One\nTwo'), [
        (text: 'One', timeMs: null),
        (text: 'Two', timeMs: null),
      ]);
    });
  });

  group('currentLineIndex', () {
    final synced = <LyricEntry>[
      (text: 'a', timeMs: 5000),
      (text: 'b', timeMs: 10000),
      (text: 'c', timeMs: 20000),
    ];

    test('is the last line that has started', () {
      expect(currentLineIndex(synced, 10000), 1);
      expect(currentLineIndex(synced, 19999), 1);
      expect(currentLineIndex(synced, 90000), 2);
    });

    test('is the first line before any has started', () {
      expect(currentLineIndex(synced, 0), 0);
    });

    test('is the first line when there is no timing', () {
      expect(
        currentLineIndex(const [
          (text: 'a', timeMs: null),
          (text: 'b', timeMs: null),
        ], 50000),
        0,
      );
    });
  });
}
