import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/desktop/linux_mini_window.dart';

import '../../helpers/fake_desktop_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late bool fullscreen, maximized, above, refuse, optionalUnsupported;
  late double width, height;
  late int resizeRequests;
  late bool restoreRequested, refuseRestore;
  late int restoreReads;

  setUp(() {
    calls = [];
    fullscreen = true;
    maximized = true;
    above = true;
    refuse = false;
    optionalUnsupported = false;
    width = 1280;
    height = 800;
    resizeRequests = 0;
    restoreRequested = false;
    refuseRestore = false;
    restoreReads = 0;
    fakeDesktopWindow((call) async {
      calls.add(call);
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'isFullScreen':
          return fullscreen;
        case 'setFullScreen':
          fullscreen = args!['isFullScreen'];
          return null;
        case 'isMaximized':
          return maximized;
        case 'unmaximize':
          maximized = false;
          return null;
        case 'maximize':
          maximized = true;
          return null;
        case 'isAlwaysOnTop':
          if (optionalUnsupported) {
            throw PlatformException(code: 'unsupported');
          }
          return above;
        case 'setAlwaysOnTop':
          above = args!['isAlwaysOnTop'];
          return null;
        case 'getBounds':
          if (restoreRequested && !refuseRestore && ++restoreReads == 3) {
            width = 1280;
            height = 800;
          }
          return {'x': 30.0, 'y': 40.0, 'width': width, 'height': height};
        case 'setBounds':
          if (args!['width'] == 320.0) {
            resizeRequests++;
            // Simulate delayed GTK hints, then an accepted configure.
            if (refuse || resizeRequests < 3) return null;
          }
          if (args['width'] == 1280.0 && refuseRestore) {
            restoreRequested = true;
            return null;
          }
          if (args['width'] == 1280.0 && restoreRequested) return null;
          width = args['width'] ?? width;
          height = args['height'] ?? height;
          return null;
      }
      return null;
    });
  });

  test(
    'native fullscreen, delayed resize and previous state restore',
    () async {
      final window = LinuxMiniWindow();
      await window.prepare();
      expect(fullscreen, isFalse);
      expect(maximized, isFalse);
      await window.enter();
      expect([width, height], [320, 340]);
      expect(resizeRequests, 3);
      await window.restore();
      expect([width, height], [1280, 800]);
      expect(maximized, isTrue);
      expect(above, isTrue);
    },
  );

  test('unsupported keep-above does not block mini mode', () async {
    optionalUnsupported = true;
    final window = LinuxMiniWindow();
    await window.prepare();
    await window.enter();
    expect(width, 320);
    await window.restore();
    expect(calls.where((c) => c.method == 'setAlwaysOnTop'), isEmpty);
  });

  test('refused resize stops retrying and can restore normal state', () async {
    refuse = true;
    final window = LinuxMiniWindow();
    await window.prepare();
    await expectLater(window.enter(), throwsStateError);
    expect(resizeRequests, 10);
    await window.restore();
    expect(maximized, isTrue);
    expect([width, height], [1280, 800]);
  });

  test(
    'restore detects ignored GTK resize and waits for a retry to settle',
    () async {
      final window = LinuxMiniWindow();
      await window.prepare();
      await window.enter();

      refuseRestore = true;
      await expectLater(window.restore(), throwsStateError);
      expect([width, height], [320, 340]);
      expect(maximized, isFalse);

      refuseRestore = false;
      await window.restore();
      expect(restoreReads, 3);
      expect([width, height], [1280, 800]);
      expect(maximized, isTrue);
    },
  );
}
