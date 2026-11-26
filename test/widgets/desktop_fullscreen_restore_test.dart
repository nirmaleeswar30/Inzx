import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/screens/widgets/desktop_player_bar.dart';
import 'package:inzx/screens/widgets/desktop_shell.dart';

import '../helpers/fake_desktop_window.dart';

void main() {
  testWidgets(
    'fullscreen cancellation, restore failure and miniplayer rollback recovery',
    (tester) async {
      final nativeFullscreenRequests = <bool>[];
      var size = const Size(1280, 800);
      var maximized = false;
      var failRestore = false;
      var failEntry = false;
      Completer<void>? restoreGate;
      var restoreStarted = false;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      fakeDesktopWindow((call) async {
        switch (call.method) {
          case 'isMaximized':
            return maximized;
          case 'maximize':
            maximized = true;
          case 'unmaximize':
            maximized = false;
          case 'isFullScreen':
          case 'isAlwaysOnTop':
            return false;
          case 'getBounds':
            return {
              'x': 0.0,
              'y': 0.0,
              'width': size.width,
              'height': size.height,
            };
          case 'setBounds':
            final width = call.arguments['width'] as double;
            final height = call.arguments['height'] as double;
            if (width == 1280) {
              restoreStarted = true;
              if (failRestore) throw PlatformException(code: 'restore-failed');
              await restoreGate?.future;
            }
            size = Size(width, height);
            if (width == 320 && failEntry) {
              throw PlatformException(code: 'resize-applied-but-entry-failed');
            }
          case 'setFullScreen':
            nativeFullscreenRequests.add(
              call.arguments['isFullScreen'] as bool,
            );
        }
        return null;
      });
      await tester.pumpWidget(const SizedBox());

      Future<void> finish(Future<void> action) async {
        var completed = false;
        final pending = action.whenComplete(() => completed = true);
        for (var i = 0; i < 60 && !completed; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(completed, isTrue, reason: 'Window transition did not finish');
        await pending;
      }

      for (final (setFullscreen, fullscreen) in [
        (setDesktopFullScreen, desktopFullScreen),
        (setDesktopVideoFullScreen, desktopVideoFullScreen),
      ]) {
        Future<void> enterMini() =>
            enterDesktopMiniMode(captureWindow: () async => null);

        await finish(enterMini());
        expect(desktopMiniMode.value, isTrue);
        final gate = restoreGate = Completer<void>();
        restoreStarted = false;
        final enter = setFullscreen(true);
        await tester.pump();
        expect(restoreStarted, isTrue);
        final cancel = setFullscreen(false);
        gate.complete();
        restoreGate = null;
        await finish(Future.wait([enter, cancel]));
        expect(desktopMiniMode.value, isFalse);
        expect(fullscreen.value, isFalse);
        expect(nativeFullscreenRequests, isEmpty);

        await finish(enterMini());
        failRestore = true;
        await finish(setFullscreen(true));
        expect(desktopMiniMode.value, isTrue);
        expect(fullscreen.value, isFalse);
        expect(nativeFullscreenRequests, isEmpty);

        failRestore = false;
        await finish(setFullscreen(true));
        expect(desktopMiniMode.value, isFalse);
        expect(fullscreen.value, isTrue);
        await finish(setFullscreen(false));
        expect(nativeFullscreenRequests, [true, false]);
        nativeFullscreenRequests.clear();
      }

      // Native resize took effect before reporting failure. If rollback also
      // fails, the next Expand must use the same saved desktop geometry.
      failEntry = true;
      failRestore = true;
      await finish(enterDesktopMiniMode(captureWindow: () async => null));
      expect(size, const Size(320, 340));
      expect(desktopMiniMode.value, isTrue);

      failRestore = false;
      await finish(exitDesktopMiniMode());
      expect(size, const Size(1280, 800));
      expect(desktopMiniMode.value, isFalse);
    },
  );
}
