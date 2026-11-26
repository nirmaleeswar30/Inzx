import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/screens/widgets/desktop_player_bar.dart';
import 'package:inzx/screens/widgets/desktop_shell.dart';

import '../helpers/fake_desktop_window.dart';

void main() {
  testWidgets('mini cycles, fullscreen guard and capture failures', (
    tester,
  ) async {
    for (final failure in <Object?>[
      null,
      const ProcessException('hyprctl', [], 'not found'),
      TimeoutException('hyprctl timed out'),
      StateError('Cannot uniquely identify the INZX window'),
    ]) {
      final calls = <MethodCall>[];
      var width = 1280.0;
      var height = 800.0;
      fakeDesktopWindow((call) async {
        calls.add(call);
        if (call.method == 'setBounds') {
          width = call.arguments['width'] ?? width;
          height = call.arguments['height'] ?? height;
        }
        return switch (call.method) {
          'isMaximized' || 'isFullScreen' || 'isAlwaysOnTop' => false,
          'getBounds' => {
            'x': 30.0,
            'y': 40.0,
            'width': width,
            'height': height,
          },
          _ => true,
        };
      });
      await tester.pumpWidget(const SizedBox());
      Future<void> finish(Future<void> action) async {
        var completed = false;
        final pending = action.then((_) => completed = true);
        for (var i = 0; i < 30 && !completed; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          completed,
          isTrue,
          reason: 'Window transition must not stay busy',
        );
        await pending;
      }

      Future<void> enter() => enterDesktopMiniMode(
        captureWindow: () async {
          if (failure != null) throw failure;
          return null;
        },
      );

      for (var cycle = 0; cycle < 3; cycle++) {
        await finish(enter());
        expect(desktopMiniMode.value, isTrue);
        await finish(exitDesktopMiniMode());
        expect(desktopMiniMode.value, isFalse);
        await finish(setDesktopFullScreen(true));
        expect(desktopFullScreen.value, isTrue);
        final before = calls.length;
        await finish(setDesktopVideoFullScreen(false));
        expect(desktopFullScreen.value, isTrue);
        expect(
          calls.length,
          before,
          reason: 'An inactive video must not exit fullscreen lyrics',
        );
        await finish(enter());
        expect(desktopFullScreen.value, isFalse);
        expect(desktopMiniMode.value, isTrue);
        await finish(setDesktopFullScreen(true));
        expect(desktopMiniMode.value, isFalse);
        await finish(setDesktopFullScreen(false));
      }
      final first = enter();
      final leave = exitDesktopMiniMode();
      final again = enter();
      await finish(Future.wait([first, leave, again]));
      expect(desktopMiniMode.value, isTrue);
      final sizes = calls.where(
        (c) => c.method == 'setBounds' && c.arguments['width'] == 320.0,
      );
      expect(sizes.length, 8);
      expect(sizes.every((c) => c.arguments['height'] == 340.0), isTrue);
      await finish(exitDesktopMiniMode());
    }
  });
}
